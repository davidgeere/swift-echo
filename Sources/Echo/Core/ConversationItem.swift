import Foundation

/// Represents a conversation item in the Realtime API.
///
/// Conversation items are used by the Realtime API to represent messages,
/// function calls, and function outputs in the conversation history.
/// These are distinct from the unified `Message` type and are used
/// specifically for WebSocket communication with the Realtime API.
public struct ConversationItem: Sendable, Codable {
    // MARK: - Properties

    /// Unique identifier for this conversation item.
    public let id: String

    /// The type of conversation item.
    public let type: ItemType

    /// The role associated with this item (for message types).
    public let role: String?

    /// Content array for this item.
    public let content: [Content]?

    /// Status of the item.
    public let status: String?

    /// Call ID for function calls.
    public let callId: String?

    /// Function name for function calls.
    public let name: String?

    /// Arguments for function calls (JSON string).
    public let arguments: String?

    /// Output from function execution (JSON string).
    public let output: String?

    // MARK: - Nested Types

    /// The type of conversation item.
    public enum ItemType: String, Codable, Sendable {
        /// A message item (user or assistant).
        case message

        /// A function call from the assistant.
        case functionCall = "function_call"

        /// Output/result from a function call.
        case functionCallOutput = "function_call_output"
    }

    /// Content within a conversation item.
    public enum Content: Sendable, Codable {
        /// Text content.
        case text(String)

        /// Audio content (base64-encoded).
        case audio(String)

        /// Input text content.
        case inputText(String)

        /// Input audio content.
        case inputAudio(String)

        // MARK: - Codable Implementation

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case audio
        }

        enum ContentType: String, Codable {
            case text
            case audio
            case inputText = "input_text"
            case inputAudio = "input_audio"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .text(let value):
                try container.encode(ContentType.text, forKey: .type)
                try container.encode(value, forKey: .text)

            case .audio(let value):
                try container.encode(ContentType.audio, forKey: .type)
                try container.encode(value, forKey: .audio)

            case .inputText(let value):
                try container.encode(ContentType.inputText, forKey: .type)
                try container.encode(value, forKey: .text)

            case .inputAudio(let value):
                try container.encode(ContentType.inputAudio, forKey: .type)
                try container.encode(value, forKey: .audio)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(ContentType.self, forKey: .type)

            switch type {
            case .text:
                let text = try container.decode(String.self, forKey: .text)
                self = .text(text)

            case .audio:
                let audio = try container.decode(String.self, forKey: .audio)
                self = .audio(audio)

            case .inputText:
                let text = try container.decode(String.self, forKey: .text)
                self = .inputText(text)

            case .inputAudio:
                let audio = try container.decode(String.self, forKey: .audio)
                self = .inputAudio(audio)
            }
        }
    }

    // MARK: - Initialization

    /// Creates a new conversation item.
    public init(
        id: String = UUID().uuidString,
        type: ItemType,
        role: String? = nil,
        content: [Content]? = nil,
        status: String? = nil,
        callId: String? = nil,
        name: String? = nil,
        arguments: String? = nil,
        output: String? = nil
    ) {
        self.id = id
        self.type = type
        self.role = role
        self.content = content
        self.status = status
        self.callId = callId
        self.name = name
        self.arguments = arguments
        self.output = output
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case content
        case status
        case callId = "call_id"
        case name
        case arguments
        case output
    }
}

// MARK: - Convenience Initializers

extension ConversationItem {
    /// Creates a message conversation item from a Message.
    public static func from(message: Message) -> ConversationItem {
        var content: [Content] = []

        // Add text content if present
        if !message.text.isEmpty {
            content.append(.text(message.text))
        }

        // Add audio content if present
        if let audioData = message.audioData {
            content.append(.audio(audioData.base64EncodedString()))
        }

        return ConversationItem(
            id: message.id,
            type: .message,
            role: message.role.rawValue,
            content: content
        )
    }

    /// Creates a text message item.
    public static func textMessage(
        id: String = UUID().uuidString,
        role: String,
        text: String
    ) -> ConversationItem {
        ConversationItem(
            id: id,
            type: .message,
            role: role,
            content: [.text(text)]
        )
    }

    /// Creates a function call item.
    public static func functionCall(
        id: String = UUID().uuidString,
        callId: String,
        name: String,
        arguments: String
    ) -> ConversationItem {
        ConversationItem(
            id: id,
            type: .functionCall,
            callId: callId,
            name: name,
            arguments: arguments
        )
    }

    /// Creates a function call output item.
    public static func functionCallOutput(
        id: String = UUID().uuidString,
        callId: String,
        output: String
    ) -> ConversationItem {
        ConversationItem(
            id: id,
            type: .functionCallOutput,
            callId: callId,
            output: output
        )
    }
}

// MARK: - Dictionary Conversion

extension ConversationItem {
    /// Converts this conversation item to a dictionary for JSON encoding.
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "type": type.rawValue
        ]

        if let role = role {
            dict["role"] = role
        }

        if let content = content {
            dict["content"] = content.map { item -> [String: Any] in
                switch item {
                case .text(let value):
                    return ["type": "text", "text": value]
                case .audio(let value):
                    return ["type": "audio", "audio": value]
                case .inputText(let value):
                    return ["type": "input_text", "text": value]
                case .inputAudio(let value):
                    return ["type": "input_audio", "audio": value]
                }
            }
        }

        if let status = status {
            dict["status"] = status
        }

        if let callId = callId {
            dict["call_id"] = callId
        }

        if let name = name {
            dict["name"] = name
        }

        if let arguments = arguments {
            dict["arguments"] = arguments
        }

        if let output = output {
            dict["output"] = output
        }

        return dict
    }
}
