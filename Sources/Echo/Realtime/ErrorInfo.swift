// ErrorInfo.swift
// Echo - Realtime API
// Error information from server events

import Foundation

public struct ErrorInfo: Sendable {
    public let code: String
    public let message: String

    static func parse(from data: [String: Any]) throws -> ErrorInfo {
        ErrorInfo(
            code: data["code"] as? String ?? "unknown",
            message: data["message"] as? String ?? "Unknown error"
        )
    }
}
