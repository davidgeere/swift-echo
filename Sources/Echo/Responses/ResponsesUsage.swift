// ResponsesUsage.swift
// Echo - Responses API
// Token usage information

import Foundation

/// Token usage information
public struct ResponsesUsage: Codable, Sendable {
    /// Input tokens consumed
    public let inputTokens: Int

    /// Output tokens generated
    public let outputTokens: Int

    /// Total tokens (input + output)
    public let totalTokens: Int

    /// Cached tokens (if applicable)
    public let cachedTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case cachedTokens = "cached_tokens"
    }

    public init(
        inputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        cachedTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
    }
}

// MARK: - CustomStringConvertible

extension ResponsesUsage: CustomStringConvertible {
    public var description: String {
        if let cached = cachedTokens {
            return "Usage(input: \(inputTokens), output: \(outputTokens), total: \(totalTokens), cached: \(cached))"
        }
        return "Usage(input: \(inputTokens), output: \(outputTokens), total: \(totalTokens))"
    }
}
