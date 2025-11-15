// ResponsesSession.swift
// Echo - Responses API
// Session management for Responses API

import Foundation

/// Represents an active session with the Responses API
public struct ResponsesSession: Sendable, Codable {
    // MARK: - Properties

    /// Session ID
    public let id: String

    /// Model being used
    public let model: ResponsesModel

    /// System instructions
    public let instructions: String?

    /// Tools available in this session
    public let tools: [ResponsesTool]

    /// Temperature setting
    public let temperature: Double

    /// Maximum output tokens
    public let maxOutputTokens: Int?

    /// Session creation time
    public let createdAt: Date

    /// Total tokens used in session
    public private(set) var totalTokensUsed: Int

    /// Number of messages in conversation
    public private(set) var messageCount: Int

    // MARK: - Initialization

    public init(
        id: String = UUID().uuidString,
        model: ResponsesModel,
        instructions: String? = nil,
        tools: [ResponsesTool] = [],
        temperature: Double = 0.8,
        maxOutputTokens: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.model = model
        self.instructions = instructions
        self.tools = tools
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.createdAt = createdAt
        self.totalTokensUsed = 0
        self.messageCount = 0
    }

    // MARK: - Mutating Methods

    /// Updates token usage
    mutating func updateTokenUsage(_ tokens: Int) {
        totalTokensUsed += tokens
    }

    /// Increments message count
    mutating func incrementMessageCount() {
        messageCount += 1
    }

    // MARK: - Computed Properties

    /// Duration of the session
    public var duration: TimeInterval {
        return Date().timeIntervalSince(createdAt)
    }

    /// Average tokens per message
    public var averageTokensPerMessage: Double {
        guard messageCount > 0 else { return 0 }
        return Double(totalTokensUsed) / Double(messageCount)
    }
}

// MARK: - CustomStringConvertible

extension ResponsesSession: CustomStringConvertible {
    public var description: String {
        return """
        ResponsesSession(
            id: \(id),
            model: \(model.rawValue),
            messages: \(messageCount),
            tokens: \(totalTokensUsed),
            duration: \(String(format: "%.1f", duration))s
        )
        """
    }
}
