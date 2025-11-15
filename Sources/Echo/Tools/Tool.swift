// Tool.swift

import Foundation

/// Represents a tool/function that can be called by the model
public struct Tool: Sendable {
    public let name: String
    public let description: String
    public let parameters: ToolParameters
    public let handler: @Sendable ([String: AnyCodable]) async throws -> String

    public init(
        name: String,
        description: String,
        parameters: ToolParameters,
        handler: @escaping @Sendable ([String: AnyCodable]) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.handler = handler
    }

    /// Convert to API format (compatible with both Realtime and Responses APIs)
    public func toAPIFormat() -> SendableJSON {
        .object([
            "type": .string("function"),
            "name": .string(name),
            "description": .string(description),
            "parameters": parameters.toJSONSchema()
        ])
    }

    /// Convert to ResponsesTool format for Responses API
    public func toResponsesTool() -> ResponsesTool {
        // Convert parameters to [String: AnyCodable]
        let paramsDict: [String: AnyCodable]
        if let dict = try? parameters.toJSONSchema().toDictionary() {
            paramsDict = dict.mapValues { AnyCodable($0) }
        } else {
            paramsDict = [:]
        }

        return ResponsesTool(
            name: name,
            description: description,
            parameters: paramsDict
        )
    }

    /// Execute the tool with provided arguments and return a ToolResult
    /// - Parameters:
    ///   - arguments: Tool arguments as SendableJSON (will be converted to AnyCodable)
    ///   - callId: The tool call ID from the API
    /// - Returns: ToolResult with output or error
    public func execute(with arguments: SendableJSON, callId: String) async -> ToolResult {
        do {
            // Convert SendableJSON to [String: AnyCodable] for handler
            let argsDict = try convertToAnyCodable(arguments)
            let output = try await handler(argsDict)
            return ToolResult(toolCallId: callId, output: output)
        } catch {
            return ToolResult(toolCallId: callId, error: error.localizedDescription)
        }
    }

    /// Convert SendableJSON to [String: AnyCodable] for handler
    private func convertToAnyCodable(_ json: SendableJSON) throws -> [String: AnyCodable] {
        guard case .object(let dict) = json else {
            throw ToolError.invalidArguments("Expected object, got \(json)")
        }

        var result: [String: AnyCodable] = [:]
        for (key, value) in dict {
            result[key] = value.toAnyCodable()
        }
        return result
    }
}

// Extension to convert SendableJSON to AnyCodable
extension SendableJSON {
    func toAnyCodable() -> AnyCodable {
        switch self {
        case .null:
            return AnyCodable(NSNull())  // Use NSNull() instead of nil
        case .bool(let value):
            return AnyCodable(value)
        case .number(let value):
            return AnyCodable(value)
        case .string(let value):
            return AnyCodable(value)
        case .array(let items):
            return AnyCodable(items.map { $0.toAnyCodable() })
        case .object(let dict):
            return AnyCodable(dict.mapValues { $0.toAnyCodable() })
        }
    }
}
