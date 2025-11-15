// ToolCall.swift

import Foundation

/// Represents a tool/function call request from the model
public struct ToolCall: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: SendableJSON

    public init(id: String, name: String, arguments: SendableJSON) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Parse arguments as a dictionary
    public func parseArguments() throws -> [String: SendableJSON] {
        guard case .object(let dict) = arguments else {
            throw ToolError.invalidArguments("Arguments must be an object")
        }
        return dict
    }
}

public enum ToolError: Error {
    case invalidArguments(String)
    case toolNotFound(String)
    case executionFailed(String)
}
