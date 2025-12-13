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
        /// Best for preventing self-interruption when using speaker
        case semanticVAD = "semantic_vad"
    }

    /// Eagerness level for semantic VAD
    /// Controls how quickly the system responds to detected speech
    public enum Eagerness: String, Sendable {
        /// Wait longer before considering user finished - best for preventing echo interruption
        case low = "low"
        /// Balanced responsiveness
        case medium = "medium"
        /// Respond quickly - use only with earpiece/headphones
        case high = "high"
    }

    // MARK: - Properties

    /// The type of VAD to use
    public let type: VADType

    /// Eagerness level for semantic VAD (ignored for server_vad)
    /// Controls how quickly the system decides the user has finished speaking
    public let eagerness: Eagerness

    /// Detection threshold (0.0 - 1.0) - for server_vad only
    /// Higher values = less sensitive (requires louder speech)
    /// Lower values = more sensitive (picks up quieter speech)
    public let threshold: Double

    /// Duration of silence (in milliseconds) before considering speech ended
    /// Only used for server_vad
    public let silenceDurationMs: Int

    /// Amount of audio (in milliseconds) to include before speech detection
    /// Only used for server_vad
    public let prefixPaddingMs: Int

    /// Whether to allow interrupting the assistant while speaking
    public let interruptResponse: Bool

    /// Whether to automatically create a response when user stops speaking
    public let createResponse: Bool

    // MARK: - Deprecated Properties

    /// Deprecated: Use `interruptResponse` instead
    @available(*, deprecated, renamed: "interruptResponse")
    public var enableInterruption: Bool {
        return interruptResponse
    }

    // MARK: - Initialization

    /// Creates a VAD configuration
    /// - Parameters:
    ///   - type: The VAD type to use (default: .serverVAD)
    ///   - eagerness: Eagerness level for semantic VAD (default: .medium)
    ///   - threshold: Detection threshold 0.0-1.0 for server_vad (default: 0.5)
    ///   - silenceDurationMs: Silence duration in ms for server_vad (default: 500)
    ///   - prefixPaddingMs: Prefix padding in ms for server_vad (default: 300)
    ///   - interruptResponse: Allow interrupting assistant (default: true)
    ///   - createResponse: Auto-create response when user stops (default: true)
    public init(
        type: VADType = .serverVAD,
        eagerness: Eagerness = .medium,
        threshold: Double = 0.5,
        silenceDurationMs: Int = 500,
        prefixPaddingMs: Int = 300,
        interruptResponse: Bool = true,
        createResponse: Bool = true
    ) {
        self.type = type
        self.eagerness = eagerness
        self.threshold = min(max(threshold, 0.0), 1.0)  // Clamp to 0.0-1.0
        self.silenceDurationMs = max(silenceDurationMs, 0)
        self.prefixPaddingMs = max(prefixPaddingMs, 0)
        self.interruptResponse = interruptResponse
        self.createResponse = createResponse
    }

    // MARK: - Presets

    /// Default VAD configuration - balanced sensitivity using server VAD
    public static let `default` = VADConfiguration(
        type: .serverVAD,
        eagerness: .medium,
        threshold: 0.5,
        silenceDurationMs: 500,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    /// Speaker-optimized configuration using semantic VAD with low eagerness
    /// Best for preventing self-interruption when using loudspeaker
    public static let speakerOptimized = VADConfiguration(
        type: .semanticVAD,
        eagerness: .low,
        threshold: 0.7,
        silenceDurationMs: 500,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    /// Earpiece/receiver configuration - more responsive server VAD
    public static let earpiece = VADConfiguration(
        type: .serverVAD,
        eagerness: .high,
        threshold: 0.5,
        silenceDurationMs: 400,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    /// Bluetooth configuration - semantic VAD with medium eagerness
    /// Good balance for Bluetooth devices which may have varying echo characteristics
    public static let bluetooth = VADConfiguration(
        type: .semanticVAD,
        eagerness: .medium,
        threshold: 0.5,
        silenceDurationMs: 500,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    /// Quiet environment configuration - more sensitive server VAD
    public static let quiet = VADConfiguration(
        type: .serverVAD,
        eagerness: .medium,
        threshold: 0.3,
        silenceDurationMs: 400,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    /// Noisy environment configuration - less sensitive server VAD
    public static let noisy = VADConfiguration(
        type: .serverVAD,
        eagerness: .low,
        threshold: 0.7,
        silenceDurationMs: 600,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    /// Patient configuration - waits longer for user to finish
    public static let patient = VADConfiguration(
        type: .serverVAD,
        eagerness: .low,
        threshold: 0.5,
        silenceDurationMs: 1000,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    /// Responsive configuration - faster turn detection
    public static let responsive = VADConfiguration(
        type: .serverVAD,
        eagerness: .high,
        threshold: 0.5,
        silenceDurationMs: 300,
        prefixPaddingMs: 200,
        interruptResponse: true,
        createResponse: true
    )

    /// Semantic VAD configuration - uses meaning-based detection with medium eagerness
    public static let semantic = VADConfiguration(
        type: .semanticVAD,
        eagerness: .medium,
        threshold: 0.5,
        silenceDurationMs: 500,
        prefixPaddingMs: 300,
        interruptResponse: true,
        createResponse: true
    )

    // MARK: - Conversion

    /// Converts to the format expected by the Realtime API
    public func toRealtimeFormat() -> [String: Any] {
        var config: [String: Any] = [
            "type": type.rawValue,
            "create_response": createResponse,
            "interrupt_response": interruptResponse
        ]

        switch type {
        case .serverVAD:
            // Server VAD uses threshold, silence duration, and prefix padding
            // Round threshold to 6 decimal places to avoid floating-point precision issues
            // (OpenAI API rejects values with more than 16 decimal places)
            let roundedThreshold = (threshold * 1_000_000).rounded() / 1_000_000
            config["threshold"] = roundedThreshold
            config["silence_duration_ms"] = silenceDurationMs
            config["prefix_padding_ms"] = prefixPaddingMs

        case .semanticVAD:
            // Semantic VAD uses eagerness instead of threshold-based params
            config["eagerness"] = eagerness.rawValue
        }

        return config
    }
}

// MARK: - CustomStringConvertible

extension VADConfiguration: CustomStringConvertible {
    public var description: String {
        switch type {
        case .serverVAD:
            return "VAD(server_vad, threshold: \(threshold), silence: \(silenceDurationMs)ms)"
        case .semanticVAD:
            return "VAD(semantic_vad, eagerness: \(eagerness.rawValue))"
        }
    }
}

// MARK: - Equatable

extension VADConfiguration: Equatable {
    public static func == (lhs: VADConfiguration, rhs: VADConfiguration) -> Bool {
        return lhs.type == rhs.type &&
               lhs.eagerness == rhs.eagerness &&
               lhs.threshold == rhs.threshold &&
               lhs.silenceDurationMs == rhs.silenceDurationMs &&
               lhs.prefixPaddingMs == rhs.prefixPaddingMs &&
               lhs.interruptResponse == rhs.interruptResponse &&
               lhs.createResponse == rhs.createResponse
    }
}
