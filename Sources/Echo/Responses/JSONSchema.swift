// JSONSchema.swift
// Echo - Responses API
// JSON schema for structured outputs

import Foundation

/// JSON schema for structured outputs
public struct JSONSchema: Codable, Sendable {
    public let name: String
    public let strict: Bool
    public let schema: [String: AnyCodable]

    public init(name: String, strict: Bool = true, schema: [String: AnyCodable]) {
        self.name = name
        self.strict = strict
        self.schema = schema
    }
}
