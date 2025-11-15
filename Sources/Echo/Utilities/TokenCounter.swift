// TokenCounter.swift

import Foundation

/// Approximate token counting (tiktoken-style estimation)
public struct TokenCounter: Sendable {
    /// Estimate token count for text
    /// Simple heuristic: ~4 characters per token on average
    public static func estimate(_ text: String) -> Int {
        return Int(ceil(Double(text.count) / 4.0))
    }

    /// Estimate token count for messages
    public static func estimate(messages: [Message]) -> Int {
        return messages.reduce(0) { total, message in
            total + estimate(message.text)
        }
    }

    /// Estimate token count for message content
    public static func estimate(content: [MessageContent]) -> Int {
        return content.reduce(0) { total, item in
            switch item {
            case .text(let text):
                return total + estimate(text)
            case .audio:
                // Audio doesn't directly count as text tokens
                return total
            case .textAndAudio(let text, _):
                return total + estimate(text)
            case .toolCall(_, let name, let arguments):
                // Estimate tokens for tool name and arguments
                return total + estimate(name) + estimate(arguments)
            case .toolResult(_, let output):
                // Estimate tokens for tool output
                return total + estimate(output)
            }
        }
    }

    /// More accurate estimation that includes message formatting overhead
    /// OpenAI charges ~4 tokens per message for formatting
    public static func estimateWithOverhead(messages: [Message]) -> Int {
        let contentTokens = estimate(messages: messages)
        let formattingOverhead = messages.count * 4
        return contentTokens + formattingOverhead
    }

    /// Estimate tokens for a single conversation turn (user + assistant)
    public static func estimateTurn(userMessage: String, assistantResponse: String) -> Int {
        return estimate(userMessage) + estimate(assistantResponse) + 8 // 2 messages * 4 tokens overhead
    }
}
