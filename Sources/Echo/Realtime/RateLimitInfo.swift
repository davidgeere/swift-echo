// RateLimitInfo.swift
// Echo - Realtime API
// Rate limit information from server events

import Foundation

public struct RateLimitInfo: Sendable {
    public let name: String
    public let limit: Int
    public let remaining: Int
    public let resetSeconds: Double

    static func parse(from data: [String: Any]) throws -> RateLimitInfo {
        RateLimitInfo(
            name: data["name"] as? String ?? "",
            limit: data["limit"] as? Int ?? 0,
            remaining: data["remaining"] as? Int ?? 0,
            resetSeconds: data["reset_seconds"] as? Double ?? 0
        )
    }
}
