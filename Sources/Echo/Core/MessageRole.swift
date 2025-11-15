// MessageRole.swift
// Echo
//
// Defines the role of a message participant in a conversation.
//

import Foundation

/// Represents the role of a message participant in a conversation.
///
/// Roles define who or what generated a message in the conversation flow.
/// This enum is compatible with both OpenAI's Realtime and Responses APIs.
public enum MessageRole: String, Codable, Sendable, CaseIterable {
    /// Message from the user/human participant.
    case user

    /// Message from the AI assistant.
    case assistant

    /// System message providing context or instructions.
    /// These messages guide the assistant's behavior but are not part of the conversation history.
    case system

    /// Message containing tool/function call results.
    /// Used when the assistant calls external functions and receives responses.
    case tool

    /// User-friendly display name for the role.
    public var displayName: String {
        switch self {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .system:
            return "System"
        case .tool:
            return "Tool"
        }
    }

    /// Whether this role represents a human participant.
    public var isHuman: Bool {
        return self == .user
    }

    /// Whether this role represents the AI assistant.
    public var isAssistant: Bool {
        return self == .assistant
    }

    /// Whether this role represents system-level instructions.
    public var isSystem: Bool {
        return self == .system
    }

    /// Whether this role represents tool/function results.
    public var isTool: Bool {
        return self == .tool
    }
}
