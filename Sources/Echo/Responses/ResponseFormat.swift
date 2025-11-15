// ResponseFormat.swift
// Echo - Responses API
// Response format configuration (for structured outputs)

import Foundation

/// Response format configuration (for structured outputs)
public struct ResponseFormat: Codable, Sendable {
    public let type: String
    public let jsonSchema: JSONSchema?

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    /// Creates a JSON object format (unstructured JSON)
    public static let jsonObject = ResponseFormat(type: "json_object", jsonSchema: nil)

    /// Creates a text format (default)
    public static let text = ResponseFormat(type: "text", jsonSchema: nil)

    /// Creates a JSON schema format (structured output)
    public static func jsonSchema(_ schema: JSONSchema) -> ResponseFormat {
        return ResponseFormat(type: "json_schema", jsonSchema: schema)
    }

    private init(type: String, jsonSchema: JSONSchema?) {
        self.type = type
        self.jsonSchema = jsonSchema
    }
}
