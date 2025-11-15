// ToolResult.swift

import Foundation

/// Result of tool execution
public struct ToolResult: Sendable {
    public let toolCallId: String
    public let output: String
    public let error: String?

    public init(toolCallId: String, output: String) {
        self.toolCallId = toolCallId
        self.output = output
        self.error = nil
    }

    public init(toolCallId: String, error: String) {
        self.toolCallId = toolCallId
        self.output = ""
        self.error = error
    }

    public var isSuccess: Bool { error == nil }

    /// Convert to API format
    public func toAPIFormat() -> SendableJSON {
        if let error = error {
            return .object([
                "type": .string("function_call_output"),
                "call_id": .string(toolCallId),
                "output": .string(""),
                "error": .string(error)
            ])
        } else {
            return .object([
                "type": .string("function_call_output"),
                "call_id": .string(toolCallId),
                "output": .string(output)
            ])
        }
    }
}
