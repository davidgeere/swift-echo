// ContentPart.swift
// Echo - Realtime API
// Content part information from server events

import Foundation

public struct ContentPart: Sendable {
    public let type: String
    public let text: String?

    static func parse(from data: [String: Any]) throws -> ContentPart {
        ContentPart(
            type: data["type"] as? String ?? "",
            text: data["text"] as? String
        )
    }
}
