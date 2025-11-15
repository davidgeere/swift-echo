// ToolChoice.swift

import Foundation

/// Specifies how the model should use tools
public enum ToolChoice: Sendable {
    case auto          // Let model decide
    case none          // Never call tools
    case required      // Must call a tool
    case specific(String)  // Call specific tool by name

    /// Convert to API format
    public var apiValue: SendableJSON {
        switch self {
        case .auto:
            return .string("auto")
        case .none:
            return .string("none")
        case .required:
            return .string("required")
        case .specific(let toolName):
            return .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string(toolName)
                ])
            ])
        }
    }
}
