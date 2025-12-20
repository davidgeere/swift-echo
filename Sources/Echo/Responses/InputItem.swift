// InputItem.swift
// Echo - Responses API
// Input items for the Responses API - supports messages and function call outputs

import Foundation

/// Input item for the Responses API.
/// Can be either a message or a function call output.
public enum InputItem: Encodable, Sendable {
    /// A conversation message
    case message(role: String, content: String)
    
    /// A function call output (tool result)
    case functionCallOutput(callId: String, output: String)
    
    // MARK: - Coding Keys
    
    enum MessageCodingKeys: String, CodingKey {
        case type
        case role
        case content
    }
    
    enum FunctionOutputCodingKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
    }
    
    // MARK: - Encoding
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let role, let content):
            var container = encoder.container(keyedBy: MessageCodingKeys.self)
            try container.encode("message", forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            
        case .functionCallOutput(let callId, let output):
            var container = encoder.container(keyedBy: FunctionOutputCodingKeys.self)
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callId, forKey: .callId)
            try container.encode(output, forKey: .output)
        }
    }
}

// MARK: - Convenience Initializers

extension InputItem {
    /// Creates an input item from a Message
    /// - Parameter message: The message to convert
    /// - Returns: An InputItem representing the message
    public static func from(message: Message) -> InputItem {
        return .message(role: message.role.rawValue, content: message.text)
    }
    
    /// Creates an input item from a tool result
    /// - Parameters:
    ///   - callId: The tool call ID
    ///   - output: The tool output
    /// - Returns: An InputItem representing the function call output
    public static func toolResult(callId: String, output: String) -> InputItem {
        return .functionCallOutput(callId: callId, output: output)
    }
}

