// ResponseInfo.swift
// Echo - Realtime API
// Response information from server events

import Foundation

public struct ResponseInfo: Sendable {
    public let id: String
    public let status: String?

    static func parse(from data: [String: Any]) throws -> ResponseInfo {
        ResponseInfo(
            id: data["id"] as? String ?? "",
            status: data["status"] as? String
        )
    }
}
