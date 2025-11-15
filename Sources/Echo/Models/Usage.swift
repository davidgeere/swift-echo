import Foundation

/// Tracks token usage and costs for API calls.
///
/// Usage information is returned by both the Realtime and Responses APIs
/// to help track consumption and estimate costs. This struct provides
/// a unified interface for both API types.
public struct Usage: Sendable, Codable {
    // MARK: - Token Counts

    /// Number of tokens in the prompt/input.
    public let promptTokens: Int

    /// Number of tokens in the completion/output.
    public let completionTokens: Int

    /// Total number of tokens used (prompt + completion).
    public let totalTokens: Int

    /// Number of tokens used for audio input (Realtime API only).
    public let audioInputTokens: Int?

    /// Number of tokens used for audio output (Realtime API only).
    public let audioOutputTokens: Int?

    /// Number of cached tokens that were reused (if applicable).
    public let cachedTokens: Int?

    // MARK: - Cost Estimation

    /// Estimated cost for this usage in USD (if cost data is available).
    public let estimatedCost: Double?

    // MARK: - Initialization

    /// Creates a new usage tracking object.
    ///
    /// - Parameters:
    ///   - promptTokens: Number of input tokens
    ///   - completionTokens: Number of output tokens
    ///   - totalTokens: Total tokens (default: computed from prompt + completion)
    ///   - audioInputTokens: Audio input tokens (Realtime API only)
    ///   - audioOutputTokens: Audio output tokens (Realtime API only)
    ///   - cachedTokens: Cached tokens reused
    ///   - estimatedCost: Estimated cost in USD
    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int? = nil,
        audioInputTokens: Int? = nil,
        audioOutputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        estimatedCost: Double? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens ?? (promptTokens + completionTokens)
        self.audioInputTokens = audioInputTokens
        self.audioOutputTokens = audioOutputTokens
        self.cachedTokens = cachedTokens
        self.estimatedCost = estimatedCost
    }

    // MARK: - Computed Properties

    /// Total audio tokens (input + output), if available.
    public var totalAudioTokens: Int? {
        guard let input = audioInputTokens, let output = audioOutputTokens else {
            return nil
        }
        return input + output
    }

    /// Whether this usage includes audio tokens.
    public var hasAudioTokens: Bool {
        return audioInputTokens != nil || audioOutputTokens != nil
    }

    /// Whether this usage includes cached tokens.
    public var hasCachedTokens: Bool {
        return cachedTokens ?? 0 > 0
    }

    /// Percentage of tokens that were cached (0.0-1.0).
    public var cacheHitRate: Double? {
        guard let cached = cachedTokens, totalTokens > 0 else {
            return nil
        }
        return Double(cached) / Double(totalTokens)
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case audioInputTokens = "audio_input_tokens"
        case audioOutputTokens = "audio_output_tokens"
        case cachedTokens = "cached_tokens"
        case estimatedCost = "estimated_cost"
    }
}

// MARK: - Zero Usage

extension Usage {
    /// Creates a zero usage object (no tokens used).
    public static var zero: Usage {
        Usage(
            promptTokens: 0,
            completionTokens: 0,
            totalTokens: 0
        )
    }
}

// MARK: - Addition

extension Usage {
    /// Adds two usage objects together.
    ///
    /// This is useful for aggregating usage across multiple API calls.
    /// Audio tokens and cached tokens are summed if present in both objects.
    /// Estimated costs are summed if present in both objects.
    public static func + (lhs: Usage, rhs: Usage) -> Usage {
        let audioInputSum = sumOptionals(lhs.audioInputTokens, rhs.audioInputTokens)
        let audioOutputSum = sumOptionals(lhs.audioOutputTokens, rhs.audioOutputTokens)
        let cachedSum = sumOptionals(lhs.cachedTokens, rhs.cachedTokens)
        let costSum = sumOptionals(lhs.estimatedCost, rhs.estimatedCost)

        return Usage(
            promptTokens: lhs.promptTokens + rhs.promptTokens,
            completionTokens: lhs.completionTokens + rhs.completionTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens,
            audioInputTokens: audioInputSum,
            audioOutputTokens: audioOutputSum,
            cachedTokens: cachedSum,
            estimatedCost: costSum
        )
    }

    /// Helper function to sum two optional integers.
    private static func sumOptionals(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case (let a?, let b?):
            return a + b
        case (let a?, nil):
            return a
        case (nil, let b?):
            return b
        case (nil, nil):
            return nil
        }
    }

    /// Helper function to sum two optional doubles.
    private static func sumOptionals(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (let a?, let b?):
            return a + b
        case (let a?, nil):
            return a
        case (nil, let b?):
            return b
        case (nil, nil):
            return nil
        }
    }
}

// MARK: - Compound Assignment

extension Usage {
    /// Adds another usage object to this one.
    public static func += (lhs: inout Usage, rhs: Usage) {
        lhs = lhs + rhs
    }
}

// MARK: - Equatable

extension Usage: Equatable {
    public static func == (lhs: Usage, rhs: Usage) -> Bool {
        return lhs.promptTokens == rhs.promptTokens &&
               lhs.completionTokens == rhs.completionTokens &&
               lhs.totalTokens == rhs.totalTokens &&
               lhs.audioInputTokens == rhs.audioInputTokens &&
               lhs.audioOutputTokens == rhs.audioOutputTokens &&
               lhs.cachedTokens == rhs.cachedTokens &&
               lhs.estimatedCost == rhs.estimatedCost
    }
}

// MARK: - CustomStringConvertible

extension Usage: CustomStringConvertible {
    public var description: String {
        var parts: [String] = [
            "Prompt: \(promptTokens)",
            "Completion: \(completionTokens)",
            "Total: \(totalTokens)"
        ]

        if let audioInput = audioInputTokens {
            parts.append("Audio Input: \(audioInput)")
        }

        if let audioOutput = audioOutputTokens {
            parts.append("Audio Output: \(audioOutput)")
        }

        if let cached = cachedTokens {
            parts.append("Cached: \(cached)")
        }

        if let cost = estimatedCost {
            parts.append(String(format: "Cost: $%.4f", cost))
        }

        return "Usage(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - UsageAccumulator

/// Accumulates usage across multiple API calls.
///
/// This class provides a thread-safe way to track cumulative usage
/// across an entire conversation or session.
public actor UsageAccumulator {
    private var accumulated: Usage = .zero

    /// The current accumulated usage.
    public var current: Usage {
        return accumulated
    }

    /// Adds usage from an API call.
    public func add(_ usage: Usage) {
        accumulated += usage
    }

    /// Resets the accumulated usage to zero.
    public func reset() {
        accumulated = .zero
    }

    /// Returns and resets the accumulated usage.
    public func flush() -> Usage {
        let current = accumulated
        accumulated = .zero
        return current
    }
}
