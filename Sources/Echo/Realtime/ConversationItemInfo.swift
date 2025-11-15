// ConversationItemInfo.swift
// Echo - Realtime API
// Conversation item information from server events

import Foundation

public struct ConversationItemInfo: Sendable {
    public let id: String
    public let type: String?
    public let role: String?

    static func parse(from data: [String: Any]) throws -> ConversationItemInfo {
        ConversationItemInfo(
            id: data["id"] as? String ?? "",
            type: data["type"] as? String,
            role: data["role"] as? String
        )
    }
}
