// SSEParser.swift
// Echo - Network Infrastructure
// Server-Sent Events (SSE) parser for streaming Responses API

import Foundation

/// Parses Server-Sent Events (SSE) from streaming HTTP responses.
/// SSE format: data: {json}\n\ndata: {json}\n\n[DONE]
public actor SSEParser {
    // MARK: - Properties

    /// Buffer for incomplete event data
    private var buffer: String = ""

    // MARK: - Parsing

    /// Appends new chunk data and extracts complete events
    /// - Parameter chunk: Raw SSE data chunk
    /// - Returns: Array of complete event data strings (JSON)
    public func parse(chunk: String) -> [String] {
        // Add chunk to buffer
        buffer += chunk

        // Extract complete events
        var events: [String] = []

        // SSE events are delimited by \n\n
        while let range = buffer.range(of: "\n\n") {
            let eventText = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)

            // Parse event lines
            if let eventData = parseEvent(eventText) {
                events.append(eventData)
            }
        }

        return events
    }

    /// Flushes any remaining buffered data as final event
    /// Call this when stream completes to get the last event if it wasn't terminated with \n\n
    /// - Returns: Array of remaining event data strings (usually 0 or 1)
    public func flush() -> [String] {
        guard !buffer.isEmpty else {
            return []
        }

        // Parse whatever is left in buffer as final event
        if let eventData = parseEvent(buffer) {
            buffer = ""  // Clear buffer after flushing
            return [eventData]
        }

        buffer = ""  // Clear buffer even if parsing failed
        return []
    }

    /// Resets the parser buffer (useful when starting new stream)
    public func reset() {
        buffer = ""
    }

    /// Returns any remaining buffered data (for debugging)
    public func remainingBuffer() -> String {
        return buffer
    }

    // MARK: - Private Helpers

    /// Parses a single SSE event block
    /// - Parameter eventText: The event text (may contain multiple lines)
    /// - Returns: The data payload if present, nil otherwise
    private func parseEvent(_ eventText: String) -> String? {
        // Split into lines
        let lines = eventText.components(separatedBy: "\n")

        var data: String?

        for line in lines {
            if line.hasPrefix("data: ") {
                // Extract data payload
                let payload = String(line.dropFirst(6)) // Remove "data: " prefix

                // Check for [DONE] marker
                if payload == "[DONE]" {
                    return nil
                }

                data = payload

            } else if line.hasPrefix("event: ") {
                // Extract event type (usually not used in OpenAI SSE) - reserved for future use
                _ = String(line.dropFirst(7))

            } else if line.hasPrefix("id: ") {
                // Event ID (usually not used in OpenAI SSE)
                continue

            } else if line.hasPrefix("retry: ") {
                // Retry interval (usually not used in OpenAI SSE)
                continue

            } else if line.isEmpty || line.hasPrefix(":") {
                // Comment or empty line - ignore
                continue
            }
        }

        return data
    }
}

// MARK: - SSE Event

/// Represents a parsed SSE event
public struct SSEEvent: Sendable {
    /// Event type (if specified)
    public let type: String?

    /// Event ID (if specified)
    public let id: String?

    /// Event data payload
    public let data: String

    /// Retry interval in milliseconds (if specified)
    public let retry: Int?

    public init(type: String? = nil, id: String? = nil, data: String, retry: Int? = nil) {
        self.type = type
        self.id = id
        self.data = data
        self.retry = retry
    }
}

// MARK: - Helper Extensions

extension SSEParser {
    /// Convenience method to parse chunk and decode JSON events
    /// - Parameters:
    ///   - chunk: Raw SSE chunk
    ///   - decoder: JSON decoder to use
    /// - Returns: Array of decoded events
    public func parseAndDecode<T: Decodable>(
        chunk: String,
        using decoder: JSONDecoder = JSONDecoder()
    ) -> [T] {
        let eventStrings = parse(chunk: chunk)

        return eventStrings.compactMap { eventData in
            guard let data = eventData.data(using: .utf8) else {
                return nil
            }

            return try? decoder.decode(T.self, from: data)
        }
    }
}
