// VADConfiguration.swift
// Echo - Realtime API
// Voice Activity Detection configuration for automatic turn detection

import Foundation

/// Configuration for Voice Activity Detection (VAD) in the Realtime API
public struct VADConfiguration: Sendable {
    // MARK: - VAD Types

    /// The type of voice activity detection to use
    public enum VADType: String, Sendable {
        /// Server-side VAD using amplitude-based detection
        case serverVAD = "server_vad"

        /// Semantic VAD that considers speech meaning and context
        case semanticVAD = "semantic_vad"
    }

    // MARK: - Properties

    /// The type of VAD to use
    public let type: VADType

    /// Detection threshold (0.0 - 1.0)
    /// Higher values = less sensitive (requires louder speech)
    /// Lower values = more sensitive (picks up quieter speech)
    public let threshold: Double

    /// Duration of silence (in milliseconds) before considering speech ended
    public let silenceDurationMs: Int

    /// Amount of audio (in milliseconds) to include before speech detection
    /// This ensures the beginning of speech is not cut off
    public let prefixPaddingMs: Int

    /// Whether to allow interrupting the assistant while speaking
    public let enableInterruption: Bool

    // MARK: - Initialization

    /// Creates a VAD configuration
    /// - Parameters:
    ///   - type: The VAD type to use (default: .serverVAD)
    ///   - threshold: Detection threshold 0.0-1.0 (default: 0.5)
    ///   - silenceDurationMs: Silence duration in ms (default: 500)
    ///   - prefixPaddingMs: Prefix padding in ms (default: 300)
    ///   - enableInterruption: Allow interruption (default: true)
    public init(
        type: VADType = .serverVAD,
        threshold: Double = 0.5,
        silenceDurationMs: Int = 500,
        prefixPaddingMs: Int = 300,
        enableInterruption: Bool = true
    ) {
        self.type = type
        self.threshold = min(max(threshold, 0.0), 1.0)  // Clamp to 0.0-1.0
        self.silenceDurationMs = max(silenceDurationMs, 0)
        self.prefixPaddingMs = max(prefixPaddingMs, 0)
        self.enableInterruption = enableInterruption
    }

    // MARK: - Presets

    /// Default VAD configuration - balanced sensitivity
    public static let `default` = VADConfiguration(
        type: .serverVAD,
        threshold: 0.5,
        silenceDurationMs: 500,
        prefixPaddingMs: 300,
        enableInterruption: true
    )

    /// Quiet environment configuration - more sensitive
    public static let quiet = VADConfiguration(
        type: .serverVAD,
        threshold: 0.3,
        silenceDurationMs: 400,
        prefixPaddingMs: 300,
        enableInterruption: true
    )

    /// Noisy environment configuration - less sensitive
    public static let noisy = VADConfiguration(
        type: .serverVAD,
        threshold: 0.7,
        silenceDurationMs: 600,
        prefixPaddingMs: 300,
        enableInterruption: true
    )

    /// Patient configuration - waits longer for user to finish
    public static let patient = VADConfiguration(
        type: .serverVAD,
        threshold: 0.5,
        silenceDurationMs: 1000,
        prefixPaddingMs: 300,
        enableInterruption: true
    )

    /// Responsive configuration - faster turn detection
    public static let responsive = VADConfiguration(
        type: .serverVAD,
        threshold: 0.5,
        silenceDurationMs: 300,
        prefixPaddingMs: 200,
        enableInterruption: true
    )

    /// Semantic VAD configuration - uses meaning-based detection
    public static let semantic = VADConfiguration(
        type: .semanticVAD,
        threshold: 0.5,
        silenceDurationMs: 500,
        prefixPaddingMs: 300,
        enableInterruption: true
    )

    // MARK: - Conversion

    /// Converts to the format expected by the Realtime API
    public func toRealtimeFormat() -> [String: Any] {
        return [
            "type": type.rawValue,
            "threshold": threshold,
            "silence_duration_ms": silenceDurationMs,
            "prefix_padding_ms": prefixPaddingMs
        ]
    }
}

// MARK: - CustomStringConvertible

extension VADConfiguration: CustomStringConvertible {
    public var description: String {
        return "VAD(\(type.rawValue), threshold: \(threshold), silence: \(silenceDurationMs)ms)"
    }
}

// MARK: - Equatable

extension VADConfiguration: Equatable {
    public static func == (lhs: VADConfiguration, rhs: VADConfiguration) -> Bool {
        return lhs.type == rhs.type &&
               lhs.threshold == rhs.threshold &&
               lhs.silenceDurationMs == rhs.silenceDurationMs &&
               lhs.prefixPaddingMs == rhs.prefixPaddingMs &&
               lhs.enableInterruption == rhs.enableInterruption
    }
}
