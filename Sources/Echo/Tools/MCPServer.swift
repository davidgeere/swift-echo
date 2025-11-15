// MCPServer.swift

import Foundation

/// Model Context Protocol server configuration
public struct MCPServer: Sendable {
    public let label: String
    public let url: URL
    public let requireApproval: ApprovalMode
    public let headers: [String: String]

    public enum ApprovalMode: String, Sendable {
        case always
        case never
        case firstTime
    }

    public init(
        label: String,
        url: URL,
        requireApproval: ApprovalMode = .never,
        headers: [String: String] = [:]
    ) {
        self.label = label
        self.url = url
        self.requireApproval = requireApproval
        self.headers = headers
    }

    /// Convert to API format (for Realtime API)
    public func toAPIFormat() -> SendableJSON {
        var headersJSON: [String: SendableJSON] = [:]
        for (key, value) in headers {
            headersJSON[key] = .string(value)
        }

        return .object([
            "type": .string("mcp"),
            "server_label": .string(label),
            "server_url": .string(url.absoluteString),
            "require_approval": .string(requireApproval.rawValue),
            "headers": .object(headersJSON)
        ])
    }

    /// Convert to ResponsesTool format for Responses API
    public func toResponsesTool() -> ResponsesTool {
        var headersDict: [String: AnyCodable] = [:]
        for (key, value) in headers {
            headersDict[key] = AnyCodable(value)
        }

        return ResponsesTool(
            name: label,
            description: "MCP Server at \(url.absoluteString)",
            parameters: [
                "type": AnyCodable("mcp"),
                "server_label": AnyCodable(label),
                "server_url": AnyCodable(url.absoluteString),
                "require_approval": AnyCodable(requireApproval.rawValue),
                "headers": AnyCodable(headersDict)
            ]
        )
    }
}
