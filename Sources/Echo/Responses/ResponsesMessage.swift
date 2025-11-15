// ResponsesMessage.swift
// Echo - Responses API
// Message in the Responses API format

import Foundation

/// Message in the Responses API format
public struct ResponsesMessage: Codable, Sendable {
    public let role: String
    public let content: [MessageContentPart]

    public init(role: String, content: [MessageContentPart]) {
        self.role = role
        self.content = content
    }

    public init(role: String, text: String) {
        self.role = role
        self.content = [.text(text)]
    }
}
