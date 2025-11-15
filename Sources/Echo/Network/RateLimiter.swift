// RateLimiter.swift
// Echo - Network Infrastructure
// Token bucket rate limiter for OpenAI API requests

import Foundation

/// Token bucket rate limiter for managing API request and token limits.
/// Tracks both requests per minute (RPM) and tokens per minute (TPM).
public actor RateLimiter {
    // MARK: - Properties

    /// Maximum requests per minute
    private let maxRequests: Int

    /// Maximum tokens per minute
    private let maxTokens: Int

    /// Current request bucket capacity
    private var requestBucket: Int

    /// Current token bucket capacity
    private var tokenBucket: Int

    /// Last time buckets were refilled
    private var lastRefill: Date

    /// Enable logging for debugging
    private let enableLogging: Bool

    // MARK: - Initialization

    /// Creates a new rate limiter with specified limits
    /// - Parameters:
    ///   - requestsPerMinute: Maximum requests per minute (default: 500)
    ///   - tokensPerMinute: Maximum tokens per minute (default: 200,000)
    ///   - enableLogging: Whether to log rate limit events
    public init(
        requestsPerMinute: Int = 500,
        tokensPerMinute: Int = 200_000,
        enableLogging: Bool = false
    ) {
        self.maxRequests = requestsPerMinute
        self.maxTokens = tokensPerMinute
        self.requestBucket = requestsPerMinute
        self.tokenBucket = tokensPerMinute
        self.lastRefill = Date()
        self.enableLogging = enableLogging
    }

    // MARK: - Rate Limiting

    /// Waits until capacity is available for a request
    /// - Parameter estimatedTokens: Estimated tokens for this request (default: 1000)
    public func waitForCapacity(estimatedTokens: Int = 1000) async throws {
        while true {
            // Refill buckets based on elapsed time
            refillBuckets()

            // Check if we have capacity
            if requestBucket >= 1 && tokenBucket >= estimatedTokens {
                // Consume capacity
                requestBucket -= 1
                tokenBucket -= estimatedTokens

                if enableLogging {
                    log("Consumed 1 request, \(estimatedTokens) tokens. Remaining: \(requestBucket) requests, \(tokenBucket) tokens")
                }

                return
            }

            if enableLogging {
                log("Rate limit reached. Waiting... (need 1 request, \(estimatedTokens) tokens; have \(requestBucket) requests, \(tokenBucket) tokens)")
            }

            // Wait 1 second and try again
            try await Task.sleep(for: .seconds(1))
        }
    }

    /// Updates rate limit state from API response headers
    /// - Parameter headers: HTTP response headers
    public func updateFromHeaders(_ headers: [String: String]) {
        // Parse remaining requests
        if let remainingRequests = headers["x-ratelimit-remaining-requests"],
           let remaining = Int(remainingRequests) {
            requestBucket = min(requestBucket, remaining)

            if enableLogging {
                log("Updated request bucket from headers: \(requestBucket)")
            }
        }

        // Parse remaining tokens
        if let remainingTokens = headers["x-ratelimit-remaining-tokens"],
           let remaining = Int(remainingTokens) {
            tokenBucket = min(tokenBucket, remaining)

            if enableLogging {
                log("Updated token bucket from headers: \(tokenBucket)")
            }
        }

        // Parse reset times (optional, for future enhancement)
        if let resetRequests = headers["x-ratelimit-reset-requests"] {
            // Could store reset time and use for more accurate refill
            if enableLogging {
                log("Request reset time: \(resetRequests)")
            }
        }

        if let resetTokens = headers["x-ratelimit-reset-tokens"] {
            // Could store reset time and use for more accurate refill
            if enableLogging {
                log("Token reset time: \(resetTokens)")
            }
        }
    }

    /// Manually refills buckets (useful for testing)
    public func refill() {
        requestBucket = maxRequests
        tokenBucket = maxTokens
        lastRefill = Date()

        if enableLogging {
            log("Manual refill: \(requestBucket) requests, \(tokenBucket) tokens")
        }
    }

    // MARK: - Diagnostics

    /// Returns current bucket capacities
    /// - Returns: Tuple of (requests, tokens) remaining
    public func currentCapacity() -> (requests: Int, tokens: Int) {
        refillBuckets()
        return (requestBucket, tokenBucket)
    }

    // MARK: - Private Helpers

    /// Refills buckets based on elapsed time
    private func refillBuckets() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)

        // Refill every 60 seconds (1 minute)
        if elapsed >= 60 {
            let previousRequests = requestBucket
            let previousTokens = tokenBucket

            requestBucket = maxRequests
            tokenBucket = maxTokens
            lastRefill = now

            if enableLogging {
                log("Refilled buckets: \(previousRequests) -> \(requestBucket) requests, \(previousTokens) -> \(tokenBucket) tokens")
            }
        }
    }

    private func log(_ message: String) {
        print("[RateLimiter] \(message)")
    }
}
