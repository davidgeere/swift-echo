// InputMessage.swift
// Echo - Responses API
// Message in the input array

import Foundation

/// Message in the input array
public struct InputMessage: Codable, Sendable {
    public let type: String = "message"
    public let role: String
    public let content: String

    enum CodingKeys: String, CodingKey {
        case type
        case role
        case content
    }

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
