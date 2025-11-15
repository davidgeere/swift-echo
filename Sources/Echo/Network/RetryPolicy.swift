// RetryPolicy.swift
// Echo - Network Infrastructure
// Exponential backoff retry policy for failed requests

import Foundation

/// Retry policy with exponential backoff and jitter for handling transient failures.
public struct RetryPolicy: Sendable {
    // MARK: - Properties

    /// Maximum number of retry attempts
    public let maxRetries: Int

    /// Base delay for first retry
    public let baseDelay: Duration

    /// Maximum delay between retries
    public let maxDelay: Duration

    /// Jitter factor (0.0 to 1.0) to add randomness to delays
    public let jitterFactor: Double

    /// Whether to retry on rate limit errors (429)
    public let retryOnRateLimit: Bool

    /// Whether to retry on server errors (5xx)
    public let retryOnServerError: Bool

    // MARK: - Presets

    /// Default retry policy (3 retries, 1s base delay)
    public static let `default` = RetryPolicy(
        maxRetries: 3,
        baseDelay: .seconds(1),
        maxDelay: .seconds(60),
        jitterFactor: 0.3,
        retryOnRateLimit: true,
        retryOnServerError: true
    )

    /// Aggressive retry policy (5 retries, shorter delays)
    public static let aggressive = RetryPolicy(
        maxRetries: 5,
        baseDelay: .milliseconds(500),
        maxDelay: .seconds(30),
        jitterFactor: 0.2,
        retryOnRateLimit: true,
        retryOnServerError: true
    )

    /// Conservative retry policy (2 retries, longer delays)
    public static let conservative = RetryPolicy(
        maxRetries: 2,
        baseDelay: .seconds(2),
        maxDelay: .seconds(120),
        jitterFactor: 0.4,
        retryOnRateLimit: true,
        retryOnServerError: false
    )

    /// No retry policy
    public static let none = RetryPolicy(
        maxRetries: 0,
        baseDelay: .seconds(0),
        maxDelay: .seconds(0),
        jitterFactor: 0,
        retryOnRateLimit: false,
        retryOnServerError: false
    )

    // MARK: - Initialization

    /// Creates a custom retry policy
    /// - Parameters:
    ///   - maxRetries: Maximum retry attempts
    ///   - baseDelay: Base delay for first retry
    ///   - maxDelay: Maximum delay cap
    ///   - jitterFactor: Randomness factor (0.0-1.0)
    ///   - retryOnRateLimit: Retry on 429 errors
    ///   - retryOnServerError: Retry on 5xx errors
    public init(
        maxRetries: Int,
        baseDelay: Duration,
        maxDelay: Duration,
        jitterFactor: Double,
        retryOnRateLimit: Bool = true,
        retryOnServerError: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = min(max(jitterFactor, 0.0), 1.0) // Clamp 0-1
        self.retryOnRateLimit = retryOnRateLimit
        self.retryOnServerError = retryOnServerError
    }

    // MARK: - Retry Logic

    /// Determines if a request should be retried based on the error
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - attempt: Current attempt number (0-indexed)
    /// - Returns: True if the request should be retried
    public func shouldRetry(error: Error, attempt: Int) -> Bool {
        // Check attempt count
        guard attempt < maxRetries else {
            return false
        }

        // Check error type
        if let httpError = error as? HTTPError {
            switch httpError {
            case .httpStatus(let code):
                // Rate limit error (429)
                if code == 429 && retryOnRateLimit {
                    return true
                }

                // Server errors (500-599)
                if code >= 500 && code < 600 && retryOnServerError {
                    return true
                }

                // Don't retry client errors (400-499, except 429)
                return false

            case .timeout:
                // Retry timeouts
                return true

            case .invalidResponse:
                // Don't retry invalid responses
                return false
            }
        }

        // Default: don't retry unknown errors
        return false
    }

    /// Calculates and waits for the appropriate delay before retry
    /// - Parameter attempt: Current attempt number (0-indexed)
    public func delayForAttempt(_ attempt: Int) async throws {
        // Convert Duration to TimeInterval (seconds), properly handling sub-second values
        let baseSeconds = baseDelay.toTimeInterval() * pow(2.0, Double(attempt))

        // Add jitter: randomize between (1-jitter) and (1+jitter)
        let jitter = Double.random(in: -jitterFactor...jitterFactor)
        let delaySeconds = baseSeconds * (1.0 + jitter)

        // Cap at max delay
        let maxDelaySeconds = maxDelay.toTimeInterval()
        let finalDelay = min(delaySeconds, maxDelaySeconds)

        // Sleep for calculated duration
        try await Task.sleep(for: .seconds(finalDelay))
    }

    /// Gets the delay duration without sleeping (useful for testing)
    /// - Parameter attempt: Current attempt number
    /// - Returns: The delay duration
    public func delayDuration(for attempt: Int) -> Duration {
        let baseSeconds = baseDelay.toTimeInterval() * pow(2.0, Double(attempt))
        let maxDelaySeconds = maxDelay.toTimeInterval()
        let finalDelay = min(baseSeconds, maxDelaySeconds)

        return .seconds(finalDelay)
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Converts Duration to TimeInterval (seconds), properly handling sub-second precision
    func toTimeInterval() -> TimeInterval {
        let (seconds, attoseconds) = self.components
        // Convert attoseconds to fractional seconds: 1 second = 10^18 attoseconds
        let fractionalSeconds = Double(attoseconds) / 1_000_000_000_000_000_000.0
        return Double(seconds) + fractionalSeconds
    }
}

// MARK: - CustomStringConvertible

extension RetryPolicy: CustomStringConvertible {
    public var description: String {
        return """
        RetryPolicy(maxRetries: \(maxRetries), \
        baseDelay: \(baseDelay), \
        maxDelay: \(maxDelay), \
        jitterFactor: \(jitterFactor), \
        retryOnRateLimit: \(retryOnRateLimit), \
        retryOnServerError: \(retryOnServerError))
        """
    }
}
