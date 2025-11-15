// ResponsesResponse.swift
// Echo - Responses API
// Response structure from the Responses API

import Foundation

/// Response from the Responses API
public struct ResponsesResponse: Codable, Sendable {
    // MARK: - Properties

    /// Unique response ID
    public let id: String

    /// Object type (always "response")
    public let object: String

    /// Model used for generation
    public let model: String

    /// Creation timestamp
    public let created: Int

    /// Output items (can be messages or reasoning)
    public let output: [OutputItem]

    /// Token usage information
    public let usage: ResponsesUsage?

    /// Status of the response
    public let status: String?

    /// Metadata
    public let metadata: [String: String]?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case model
        case created = "created_at"
        case output
        case usage
        case status
        case metadata
    }

    // MARK: - Convenience

    /// Returns the first text output, if available
    public var firstText: String? {
        for item in output {
            if case .message(let message) = item {
                return message.content.first(where: {
                    if case .text = $0 { return true }
                    return false
                }).flatMap {
                    if case .text(let text) = $0 { return text }
                    return nil
                }
            }
        }
        return nil
    }

    /// Returns all text content concatenated
    public var allText: String {
        return output.compactMap { item in
            if case .message(let message) = item {
                return message.content.compactMap { part in
                    if case .text(let text) = part { return text }
                    return nil
                }.joined()
            }
            return nil
        }.joined(separator: "\n")
    }

    /// Creation date
    public var createdDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(created))
    }
}

// MARK: - CustomStringConvertible

extension ResponsesResponse: CustomStringConvertible {
    public var description: String {
        return """
        ResponsesResponse(
            id: \(id),
            model: \(model),
            status: \(status ?? "unknown"),
            output: \(output.count) message(s),
            usage: \(usage?.totalTokens ?? 0) tokens
        )
        """
    }
}

// Note: Supporting types are defined in separate files:
// - ResponsesUsage.swift
// - OutputItem.swift
