// ResponsesTool.swift
// Echo - Responses API
// Tool definition for function calling

import Foundation

/// Tool definition for function calling
/// Note: Responses API uses flat structure (not nested like Chat Completions API)
public struct ResponsesTool: Codable, Sendable {
    public let name: String
    public let description: String?
    public let parameters: [String: AnyCodable]?
    public let type: String

    public init(name: String, description: String?, parameters: [String: AnyCodable]?) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.type = "function"
    }
}
