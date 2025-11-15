// ToolDefinition.swift

import Foundation

/// Defines the schema for tool parameters
public struct ToolParameters: Sendable {
    public let type: String = "object"
    public let properties: [String: ParameterSchema]
    public let required: [String]

    public init(properties: [String: ParameterSchema], required: [String] = []) {
        self.properties = properties
        self.required = required
    }

    /// Convert to JSON schema format
    public func toJSONSchema() -> SendableJSON {
        .object([
            "type": .string(type),
            "properties": .object(properties.mapValues { $0.toJSONSchema() }),
            "required": .array(required.map { .string($0) })
        ])
    }
}

/// Schema for individual parameters
public indirect enum ParameterSchema: Sendable {
    case string(description: String)
    case number(description: String)
    case boolean(description: String)
    case enumeration(values: [String], description: String)
    case object(properties: [String: ParameterSchema])
    case array(itemType: ParameterSchema)

    /// Convert to JSON schema format
    public func toJSONSchema() -> SendableJSON {
        switch self {
        case .string(let description):
            return .object([
                "type": .string("string"),
                "description": .string(description)
            ])
        case .number(let description):
            return .object([
                "type": .string("number"),
                "description": .string(description)
            ])
        case .boolean(let description):
            return .object([
                "type": .string("boolean"),
                "description": .string(description)
            ])
        case .enumeration(let values, let description):
            return .object([
                "type": .string("string"),
                "enum": .array(values.map { .string($0) }),
                "description": .string(description)
            ])
        case .object(let properties):
            return .object([
                "type": .string("object"),
                "properties": .object(properties.mapValues { $0.toJSONSchema() })
            ])
        case .array(let itemType):
            return .object([
                "type": .string("array"),
                "items": itemType.toJSONSchema()
            ])
        }
    }
}
