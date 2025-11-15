import Foundation

/// Represents different types of content that can be included in a message.
///
/// Messages can contain text, audio data, or both. This type is used for both
/// Realtime and Responses APIs, enabling mode-agnostic message handling.
public enum MessageContent: Sendable, Codable {
    /// Text content.
    case text(String)

    /// Audio data content (base64-encoded PCM16 or G.711).
    case audio(Data)

    /// Combined text and audio content.
    /// Used when a message has both transcribed text and original audio.
    case textAndAudio(text: String, audio: Data)

    /// Tool call information.
    case toolCall(id: String, name: String, arguments: String)

    /// Tool call result.
    case toolResult(id: String, output: String)

    // MARK: - Computed Properties

    /// The text content, if available.
    public var text: String? {
        switch self {
        case .text(let value):
            return value
        case .textAndAudio(let text, _):
            return text
        default:
            return nil
        }
    }

    /// The audio data, if available.
    public var audioData: Data? {
        switch self {
        case .audio(let data):
            return data
        case .textAndAudio(_, let audio):
            return audio
        default:
            return nil
        }
    }

    /// Whether this content includes text.
    public var hasText: Bool {
        return text != nil
    }

    /// Whether this content includes audio.
    public var hasAudio: Bool {
        return audioData != nil
    }

    /// Whether this content represents a tool call.
    public var isToolCall: Bool {
        if case .toolCall = self {
            return true
        }
        return false
    }

    /// Whether this content represents a tool result.
    public var isToolResult: Bool {
        if case .toolResult = self {
            return true
        }
        return false
    }

    // MARK: - Codable Implementation

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case audio
        case toolCallId
        case toolName
        case arguments
        case output
    }

    enum ContentType: String, Codable {
        case text
        case audio
        case textAndAudio
        case toolCall
        case toolResult
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(value, forKey: .text)

        case .audio(let data):
            try container.encode(ContentType.audio, forKey: .type)
            try container.encode(data, forKey: .audio)

        case .textAndAudio(let text, let audio):
            try container.encode(ContentType.textAndAudio, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(audio, forKey: .audio)

        case .toolCall(let id, let name, let arguments):
            try container.encode(ContentType.toolCall, forKey: .type)
            try container.encode(id, forKey: .toolCallId)
            try container.encode(name, forKey: .toolName)
            try container.encode(arguments, forKey: .arguments)

        case .toolResult(let id, let output):
            try container.encode(ContentType.toolResult, forKey: .type)
            try container.encode(id, forKey: .toolCallId)
            try container.encode(output, forKey: .output)
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
            let audio = try container.decode(Data.self, forKey: .audio)
            self = .audio(audio)

        case .textAndAudio:
            let text = try container.decode(String.self, forKey: .text)
            let audio = try container.decode(Data.self, forKey: .audio)
            self = .textAndAudio(text: text, audio: audio)

        case .toolCall:
            let id = try container.decode(String.self, forKey: .toolCallId)
            let name = try container.decode(String.self, forKey: .toolName)
            let arguments = try container.decode(String.self, forKey: .arguments)
            self = .toolCall(id: id, name: name, arguments: arguments)

        case .toolResult:
            let id = try container.decode(String.self, forKey: .toolCallId)
            let output = try container.decode(String.self, forKey: .output)
            self = .toolResult(id: id, output: output)
        }
    }
}

// MARK: - Equatable

extension MessageContent: Equatable {
    public static func == (lhs: MessageContent, rhs: MessageContent) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lText), .text(let rText)):
            return lText == rText
        case (.audio(let lData), .audio(let rData)):
            return lData == rData
        case (.textAndAudio(let lText, let lAudio), .textAndAudio(let rText, let rAudio)):
            return lText == rText && lAudio == rAudio
        case (.toolCall(let lId, let lName, let lArgs), .toolCall(let rId, let rName, let rArgs)):
            return lId == rId && lName == rName && lArgs == rArgs
        case (.toolResult(let lId, let lOutput), .toolResult(let rId, let rOutput)):
            return lId == rId && lOutput == rOutput
        default:
            return false
        }
    }
}
