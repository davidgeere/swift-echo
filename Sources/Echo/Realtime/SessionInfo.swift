// SessionInfo.swift
// Echo - Realtime API
// Session information from server events

import Foundation

public struct SessionInfo: Sendable {
    public let id: String
    public let model: String?
    public let voice: String?

    static func parse(from data: [String: Any]) throws -> SessionInfo {
        SessionInfo(
            id: data["id"] as? String ?? "",
            model: data["model"] as? String,
            voice: data["voice"] as? String
        )
    }
}
