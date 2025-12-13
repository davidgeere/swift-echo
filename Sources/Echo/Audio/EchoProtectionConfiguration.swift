// EchoProtectionConfiguration.swift
// Echo - Audio
// Configuration for acoustic echo protection when using speaker output

import Foundation

/// Echo protection mode determining which algorithm is used
///
/// Different modes offer different trade-offs between accuracy and compatibility.
public enum EchoProtectionMode: String, Sendable {
    /// Uses RMS threshold-based gating (original method)
    ///
    /// Simple and fast, but can fail when:
    /// - Echo is loud (passes through as "speech")
    /// - User speaks quietly (gets blocked as "echo")
    case threshold

    /// Uses correlation-based echo cancellation
    ///
    /// Compares microphone input with recently played audio to detect echo
    /// by waveform pattern matching. More accurate than threshold-based gating.
    case correlation

    /// Uses both threshold AND correlation (most robust)
    ///
    /// First applies threshold gating for quick filtering, then uses
    /// correlation analysis for remaining audio. Provides best coverage
    /// but uses more CPU.
    case hybrid
}

/// Configuration for acoustic echo protection when using speaker output
///
/// When the assistant speaks through the speaker, the microphone may pick up this
/// audio and the VAD could interpret it as user speech, causing self-interruption.
/// Echo protection provides client-side gating to filter out this echo while still
/// allowing genuine user barge-in.
///
/// ## Echo Protection Modes
///
/// - **Threshold**: Simple RMS-based gating (fast, but can miss loud echo)
/// - **Correlation**: Waveform pattern matching (more accurate, handles loud echo)
/// - **Hybrid**: Uses both methods (most robust, slightly higher CPU usage)
///
/// ## Example Usage
///
/// ```swift
/// // Use correlation-based echo protection
/// let config = EchoProtectionConfiguration(
///     mode: .correlation,
///     correlationConfig: .default
/// )
///
/// // Use hybrid mode for maximum robustness
/// let config = EchoProtectionConfiguration.correlationDefault
/// ```
public struct EchoProtectionConfiguration: Sendable {
    // MARK: - Properties

    /// Whether echo protection is enabled
    public let enabled: Bool

    /// The echo protection mode to use
    public let mode: EchoProtectionMode

    /// RMS level threshold for barge-in during assistant speech
    ///
    /// Only audio louder than this threshold will be forwarded to the server
    /// during assistant speech. Echo is typically 0.05-0.1 RMS, while direct
    /// speech into the microphone is typically 0.2+ RMS.
    ///
    /// Used when mode is `.threshold` or `.hybrid`.
    ///
    /// Range: 0.0-1.0, default: 0.15
    public let bargeInThreshold: Float

    /// Delay after assistant stops speaking before disabling the gate
    ///
    /// This delay allows echo to fully decay before resuming normal audio
    /// capture sensitivity.
    public let postSpeechDelay: Duration

    /// Configuration for the correlation-based echo canceller
    ///
    /// Used when mode is `.correlation` or `.hybrid`.
    public let correlationConfig: EchoCancellerConfiguration?

    // MARK: - Initialization

    /// Creates an echo protection configuration
    /// - Parameters:
    ///   - enabled: Whether echo protection is enabled (default: true)
    ///   - mode: The echo protection mode to use (default: .hybrid)
    ///   - bargeInThreshold: RMS level threshold for barge-in (default: 0.15)
    ///   - postSpeechDelay: Delay after assistant stops speaking (default: 300ms)
    ///   - correlationConfig: Configuration for correlation-based cancellation
    public init(
        enabled: Bool = true,
        mode: EchoProtectionMode = .hybrid,
        bargeInThreshold: Float = 0.15,
        postSpeechDelay: Duration = .milliseconds(300),
        correlationConfig: EchoCancellerConfiguration? = nil
    ) {
        self.enabled = enabled
        self.mode = mode
        self.bargeInThreshold = min(max(bargeInThreshold, 0.0), 1.0)  // Clamp to 0.0-1.0
        self.postSpeechDelay = postSpeechDelay

        // Auto-assign correlation config based on mode
        if mode == .correlation || mode == .hybrid {
            self.correlationConfig = correlationConfig ?? .default
        } else {
            self.correlationConfig = correlationConfig
        }
    }

    // MARK: - Presets

    /// Default echo protection - threshold-based for backward compatibility
    public static let `default` = EchoProtectionConfiguration(
        enabled: true,
        mode: .threshold,
        bargeInThreshold: 0.15,
        postSpeechDelay: .milliseconds(300),
        correlationConfig: nil
    )

    /// Correlation-based echo protection - uses waveform pattern matching
    public static let correlationDefault = EchoProtectionConfiguration(
        enabled: true,
        mode: .correlation,
        bargeInThreshold: 0.15,
        postSpeechDelay: .milliseconds(300),
        correlationConfig: .default
    )

    /// Hybrid echo protection - uses both threshold and correlation
    ///
    /// Most robust option, recommended for speaker output.
    public static let hybrid = EchoProtectionConfiguration(
        enabled: true,
        mode: .hybrid,
        bargeInThreshold: 0.15,
        postSpeechDelay: .milliseconds(300),
        correlationConfig: .default
    )

    /// Aggressive echo protection for high volume speaker situations
    /// Uses higher threshold, longer delay, and more sensitive correlation
    public static let aggressive = EchoProtectionConfiguration(
        enabled: true,
        mode: .hybrid,
        bargeInThreshold: 0.25,
        postSpeechDelay: .milliseconds(500),
        correlationConfig: .aggressive
    )

    /// Light echo protection for lower volume or better acoustic environments
    public static let light = EchoProtectionConfiguration(
        enabled: true,
        mode: .threshold,
        bargeInThreshold: 0.10,
        postSpeechDelay: .milliseconds(200),
        correlationConfig: nil
    )

    /// Disabled echo protection (use only with earpiece/headphones)
    public static let disabled = EchoProtectionConfiguration(
        enabled: false,
        mode: .threshold,
        bargeInThreshold: 0.0,
        postSpeechDelay: .zero,
        correlationConfig: nil
    )

    // MARK: - Convenience Properties

    /// Whether threshold-based gating should be used
    public var usesThreshold: Bool {
        enabled && (mode == .threshold || mode == .hybrid)
    }

    /// Whether correlation-based cancellation should be used
    public var usesCorrelation: Bool {
        enabled && (mode == .correlation || mode == .hybrid) && correlationConfig != nil
    }
}

// MARK: - CustomStringConvertible

extension EchoProtectionConfiguration: CustomStringConvertible {
    public var description: String {
        if enabled {
            switch mode {
            case .threshold:
                return "EchoProtection(mode: threshold, threshold: \(bargeInThreshold), delay: \(postSpeechDelay))"
            case .correlation:
                return "EchoProtection(mode: correlation, config: \(correlationConfig?.description ?? "nil"))"
            case .hybrid:
                return "EchoProtection(mode: hybrid, threshold: \(bargeInThreshold), config: \(correlationConfig?.description ?? "nil"))"
            }
        } else {
            return "EchoProtection(disabled)"
        }
    }
}

// MARK: - Equatable

extension EchoProtectionConfiguration: Equatable {
    public static func == (lhs: EchoProtectionConfiguration, rhs: EchoProtectionConfiguration) -> Bool {
        return lhs.enabled == rhs.enabled &&
               lhs.mode == rhs.mode &&
               lhs.bargeInThreshold == rhs.bargeInThreshold &&
               lhs.postSpeechDelay == rhs.postSpeechDelay &&
               lhs.correlationConfig == rhs.correlationConfig
    }
}
