// EchoProtectionConfiguration.swift
// Echo - Audio
// Configuration for acoustic echo protection when using speaker output

import Foundation

/// Configuration for acoustic echo protection when using speaker output
///
/// When the assistant speaks through the speaker, the microphone may pick up this
/// audio and the VAD could interpret it as user speech, causing self-interruption.
/// Echo protection provides client-side gating to filter out this echo while still
/// allowing genuine user barge-in.
public struct EchoProtectionConfiguration: Sendable {
    // MARK: - Properties

    /// Whether echo protection is enabled
    public let enabled: Bool

    /// RMS level threshold for barge-in during assistant speech
    ///
    /// Only audio louder than this threshold will be forwarded to the server
    /// during assistant speech. Echo is typically 0.05-0.1 RMS, while direct
    /// speech into the microphone is typically 0.2+ RMS.
    ///
    /// Range: 0.0-1.0, default: 0.15
    public let bargeInThreshold: Float

    /// Delay after assistant stops speaking before disabling the gate
    ///
    /// This delay allows echo to fully decay before resuming normal audio
    /// capture sensitivity.
    public let postSpeechDelay: Duration

    // MARK: - Initialization

    /// Creates an echo protection configuration
    /// - Parameters:
    ///   - enabled: Whether echo protection is enabled (default: true)
    ///   - bargeInThreshold: RMS level threshold for barge-in (default: 0.15)
    ///   - postSpeechDelay: Delay after assistant stops speaking (default: 300ms)
    public init(
        enabled: Bool = true,
        bargeInThreshold: Float = 0.15,
        postSpeechDelay: Duration = .milliseconds(300)
    ) {
        self.enabled = enabled
        self.bargeInThreshold = min(max(bargeInThreshold, 0.0), 1.0)  // Clamp to 0.0-1.0
        self.postSpeechDelay = postSpeechDelay
    }

    // MARK: - Presets

    /// Default echo protection - balanced threshold
    public static let `default` = EchoProtectionConfiguration(
        enabled: true,
        bargeInThreshold: 0.15,
        postSpeechDelay: .milliseconds(300)
    )

    /// Aggressive echo protection for high volume speaker situations
    /// Uses higher threshold and longer delay
    public static let aggressive = EchoProtectionConfiguration(
        enabled: true,
        bargeInThreshold: 0.25,
        postSpeechDelay: .milliseconds(500)
    )

    /// Light echo protection for lower volume or better acoustic environments
    public static let light = EchoProtectionConfiguration(
        enabled: true,
        bargeInThreshold: 0.10,
        postSpeechDelay: .milliseconds(200)
    )

    /// Disabled echo protection (use only with earpiece/headphones)
    public static let disabled = EchoProtectionConfiguration(
        enabled: false,
        bargeInThreshold: 0.0,
        postSpeechDelay: .zero
    )
}

// MARK: - CustomStringConvertible

extension EchoProtectionConfiguration: CustomStringConvertible {
    public var description: String {
        if enabled {
            return "EchoProtection(threshold: \(bargeInThreshold), delay: \(postSpeechDelay))"
        } else {
            return "EchoProtection(disabled)"
        }
    }
}

// MARK: - Equatable

extension EchoProtectionConfiguration: Equatable {
    public static func == (lhs: EchoProtectionConfiguration, rhs: EchoProtectionConfiguration) -> Bool {
        return lhs.enabled == rhs.enabled &&
               lhs.bargeInThreshold == rhs.bargeInThreshold &&
               lhs.postSpeechDelay == rhs.postSpeechDelay
    }
}

