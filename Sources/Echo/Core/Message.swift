// Message.swift
// Echo
//
// Unified message model for the Echo library.
//

import Foundation

/// A unified message model that works across both audio and text modes.
///
/// Messages are the core building block of Echo conversations. They can contain:
/// - Text content (from text mode or transcribed from audio mode)
/// - Audio data (from audio mode interactions)
/// - Tool call information and results
///
/// Messages are immutable and include metadata for proper sequencing and display.
/// The sequence number ensures correct ordering even when transcriptions arrive
/// out of order relative to assistant responses.
public struct Message: Sendable, Identifiable, Codable {
    // MARK: - Properties

    /// Unique identifier for this message.
    public let id: String

    /// The role of the message sender (user, assistant, system, or tool).
    public let role: MessageRole

    /// Text content of the message.
    /// For audio messages, this contains the transcribed text.
    public let text: String

    /// Optional audio data for voice messages (base64-encoded PCM16 or G.711).
    /// Only present for messages from audio mode.
    public let audioData: Data?

    /// Timestamp when the message was created.
    public let timestamp: Date

    /// Sequence number for maintaining correct message order.
    /// Critical for audio mode where transcripts may arrive after assistant responses.
    public let sequenceNumber: Int

    /// Optional content array for rich message types.
    /// Used when a message contains multiple content parts (text + audio, tool calls, etc.).
    public let content: [MessageContent]?

    // MARK: - Initialization

    /// Creates a new message with the specified properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (default: UUID)
    ///   - role: The role of the message sender
    ///   - text: Text content of the message
    ///   - audioData: Optional audio data for voice messages
    ///   - timestamp: Timestamp when created (default: now)
    ///   - sequenceNumber: Sequence number for ordering
    ///   - content: Optional rich content array
    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        text: String,
        audioData: Data? = nil,
        timestamp: Date = Date(),
        sequenceNumber: Int,
        content: [MessageContent]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.audioData = audioData
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
        self.content = content
    }

    // MARK: - Computed Properties

    /// Whether this message includes audio data.
    public var hasAudio: Bool {
        return audioData != nil
    }

    /// Whether this message has text content.
    public var hasText: Bool {
        return !text.isEmpty
    }

    /// Whether this message is from the user.
    public var isFromUser: Bool {
        return role == .user
    }

    /// Whether this message is from the assistant.
    public var isFromAssistant: Bool {
        return role == .assistant
    }

    /// Whether this message is a system message.
    public var isSystemMessage: Bool {
        return role == .system
    }

    /// Whether this message is a tool result.
    public var isToolMessage: Bool {
        return role == .tool
    }

    // MARK: - API Conversion

    /// Converts this message to the format expected by the Responses API.
    public func toResponsesFormat() -> [String: Any] {
        var result: [String: Any] = [
            "role": role.rawValue,
            "content": text
        ]

        // Include content array if present
        if let content = content, !content.isEmpty {
            result["content"] = content.map { contentItem in
                switch contentItem {
                case .text(let value):
                    return ["type": "text", "text": value]
                case .audio(let data):
                    return ["type": "audio", "audio": data.base64EncodedString()]
                case .textAndAudio(let text, let audio):
                    return [
                        "type": "text_and_audio",
                        "text": text,
                        "audio": audio.base64EncodedString()
                    ]
                case .toolCall(let id, let name, let arguments):
                    return [
                        "type": "tool_call",
                        "id": id,
                        "name": name,
                        "arguments": arguments
                    ]
                case .toolResult(let id, let output):
                    return [
                        "type": "tool_result",
                        "id": id,
                        "output": output
                    ]
                }
            }
        }

        return result
    }

    /// Converts this message to the format expected by the Realtime API.
    public func toRealtimeFormat() -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "type": "message",
            "role": role.rawValue
        ]

        var contentArray: [[String: Any]] = []

        // Add text content if present
        if !text.isEmpty {
            contentArray.append(["type": "text", "text": text])
        }

        // Add audio content if present
        if let audioData = audioData {
            contentArray.append([
                "type": "audio",
                "audio": audioData.base64EncodedString()
            ])
        }

        if !contentArray.isEmpty {
            result["content"] = contentArray
        }

        return result
    }
}

// MARK: - Equatable

extension Message: Equatable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension Message: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Convenience Initializers

extension Message {
    /// Creates a user message with text content.
    public static func user(
        text: String,
        sequenceNumber: Int,
        timestamp: Date = Date()
    ) -> Message {
        Message(
            role: .user,
            text: text,
            timestamp: timestamp,
            sequenceNumber: sequenceNumber
        )
    }

    /// Creates an assistant message with text content.
    public static func assistant(
        text: String,
        sequenceNumber: Int,
        timestamp: Date = Date()
    ) -> Message {
        Message(
            role: .assistant,
            text: text,
            timestamp: timestamp,
            sequenceNumber: sequenceNumber
        )
    }

    /// Creates a system message with instructions.
    public static func system(
        text: String,
        sequenceNumber: Int = 0,
        timestamp: Date = Date()
    ) -> Message {
        Message(
            role: .system,
            text: text,
            timestamp: timestamp,
            sequenceNumber: sequenceNumber
        )
    }

    /// Creates a tool result message.
    public static func tool(
        text: String,
        sequenceNumber: Int,
        timestamp: Date = Date()
    ) -> Message {
        Message(
            role: .tool,
            text: text,
            timestamp: timestamp,
            sequenceNumber: sequenceNumber
        )
    }
}
