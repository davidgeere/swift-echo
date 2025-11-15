// ConversationInfo.swift
// Echo - Realtime API
// Conversation information from server events

import Foundation

public struct ConversationInfo: Sendable {
    public let id: String

    static func parse(from data: [String: Any]) throws -> ConversationInfo {
        ConversationInfo(id: data["id"] as? String ?? "")
    }
}
