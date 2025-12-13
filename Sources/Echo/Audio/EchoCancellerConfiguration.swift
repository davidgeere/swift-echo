// EchoCancellerConfiguration.swift
// Echo - Audio
// Configuration for the correlation-based echo canceller

import Foundation

/// Configuration for the correlation-based echo canceller
///
/// Controls the behavior of the `EchoCanceller` including:
/// - How much reference audio to keep for correlation
/// - The correlation threshold for echo detection
/// - The delay range to search for echo
///
/// ## Example Usage
///
/// ```swift
/// // Use default settings
/// let canceller = EchoCanceller(configuration: .default)
///
/// // Use aggressive settings for noisy environments
/// let canceller = EchoCanceller(configuration: .aggressive)
///
/// // Custom configuration
/// let config = EchoCancellerConfiguration(
///     correlationThreshold: 0.7,
///     maxReferenceDurationMs: 600
/// )
/// let canceller = EchoCanceller(configuration: config)
/// ```
public struct EchoCancellerConfiguration: Sendable {
    // MARK: - Properties
    
    /// Whether the correlation-based echo canceller is enabled
    ///
    /// When disabled, the `EchoCanceller` will not perform any processing.
    public let enabled: Bool
    
    /// Audio sample rate in Hz
    ///
    /// Must match the audio format being used. OpenAI Realtime uses 24kHz.
    public let sampleRate: Float
    
    /// Correlation threshold above which audio is considered echo
    ///
    /// Value between 0.0 and 1.0. Higher values require stronger correlation
    /// to trigger echo detection, reducing false positives but potentially
    /// allowing more echo through.
    ///
    /// Typical values:
    /// - 0.5: Very sensitive, may have false positives
    /// - 0.65: Balanced (default)
    /// - 0.75: Conservative, fewer false positives
    public let correlationThreshold: Float
    
    /// Maximum duration of reference audio to keep (in milliseconds)
    ///
    /// Longer durations allow detecting echo with longer delays (larger rooms)
    /// but use more memory. 500ms is sufficient for most environments.
    public let maxReferenceDurationMs: Int
    
    /// Minimum echo delay to search for (in milliseconds)
    ///
    /// Echo can't arrive faster than the speed of sound allows.
    /// 5ms corresponds to ~1.7 meters distance.
    public let minDelayMs: Int
    
    /// Maximum echo delay to search for (in milliseconds)
    ///
    /// Larger delays correspond to larger rooms or more reverb.
    /// 100ms covers most typical room sizes.
    public let maxDelayMs: Int
    
    // MARK: - Initialization
    
    /// Creates an echo canceller configuration
    ///
    /// - Parameters:
    ///   - enabled: Whether echo cancellation is enabled (default: true)
    ///   - sampleRate: Audio sample rate in Hz (default: 24000)
    ///   - correlationThreshold: Threshold for echo detection (default: 0.65)
    ///   - maxReferenceDurationMs: Reference buffer duration in ms (default: 500)
    ///   - minDelayMs: Minimum delay to search in ms (default: 5)
    ///   - maxDelayMs: Maximum delay to search in ms (default: 100)
    public init(
        enabled: Bool = true,
        sampleRate: Float = 24000,
        correlationThreshold: Float = 0.65,
        maxReferenceDurationMs: Int = 500,
        minDelayMs: Int = 5,
        maxDelayMs: Int = 100
    ) {
        self.enabled = enabled
        self.sampleRate = sampleRate
        self.correlationThreshold = min(max(correlationThreshold, 0.0), 1.0)
        self.maxReferenceDurationMs = max(100, maxReferenceDurationMs)
        self.minDelayMs = max(1, minDelayMs)
        self.maxDelayMs = max(minDelayMs + 10, maxDelayMs)
    }
    
    // MARK: - Presets
    
    /// Default configuration - balanced for most environments
    ///
    /// Uses 0.65 correlation threshold with 500ms reference buffer.
    /// Suitable for typical phone speaker usage.
    public static let `default` = EchoCancellerConfiguration(
        enabled: true,
        sampleRate: 24000,
        correlationThreshold: 0.65,
        maxReferenceDurationMs: 500,
        minDelayMs: 5,
        maxDelayMs: 100
    )
    
    /// Aggressive configuration for challenging acoustic environments
    ///
    /// Uses lower threshold (more sensitive) with longer reference buffer.
    /// Better for large rooms or high speaker volume.
    public static let aggressive = EchoCancellerConfiguration(
        enabled: true,
        sampleRate: 24000,
        correlationThreshold: 0.55,
        maxReferenceDurationMs: 750,
        minDelayMs: 5,
        maxDelayMs: 150
    )
    
    /// Conservative configuration to minimize false positives
    ///
    /// Uses higher threshold (less sensitive).
    /// Better for quieter environments or when user interruption is critical.
    public static let conservative = EchoCancellerConfiguration(
        enabled: true,
        sampleRate: 24000,
        correlationThreshold: 0.75,
        maxReferenceDurationMs: 400,
        minDelayMs: 5,
        maxDelayMs: 80
    )
    
    /// Near-field configuration for phone held close to face
    ///
    /// Shorter delay range since echo arrives quickly.
    public static let nearField = EchoCancellerConfiguration(
        enabled: true,
        sampleRate: 24000,
        correlationThreshold: 0.65,
        maxReferenceDurationMs: 300,
        minDelayMs: 3,
        maxDelayMs: 50
    )
    
    /// Far-field configuration for speakerphone or Bluetooth speaker
    ///
    /// Longer delay range for room acoustics.
    public static let farField = EchoCancellerConfiguration(
        enabled: true,
        sampleRate: 24000,
        correlationThreshold: 0.60,
        maxReferenceDurationMs: 750,
        minDelayMs: 10,
        maxDelayMs: 150
    )
    
    /// Disabled configuration
    ///
    /// Use this when echo cancellation is not needed (e.g., earpiece, headphones).
    public static let disabled = EchoCancellerConfiguration(
        enabled: false,
        sampleRate: 24000,
        correlationThreshold: 0.65,
        maxReferenceDurationMs: 500,
        minDelayMs: 5,
        maxDelayMs: 100
    )
}

// MARK: - CustomStringConvertible

extension EchoCancellerConfiguration: CustomStringConvertible {
    public var description: String {
        if enabled {
            return "EchoCancellerConfig(threshold: \(correlationThreshold), buffer: \(maxReferenceDurationMs)ms, delay: \(minDelayMs)-\(maxDelayMs)ms)"
        } else {
            return "EchoCancellerConfig(disabled)"
        }
    }
}

// MARK: - Equatable

extension EchoCancellerConfiguration: Equatable {
    public static func == (lhs: EchoCancellerConfiguration, rhs: EchoCancellerConfiguration) -> Bool {
        return lhs.enabled == rhs.enabled &&
               lhs.sampleRate == rhs.sampleRate &&
               lhs.correlationThreshold == rhs.correlationThreshold &&
               lhs.maxReferenceDurationMs == rhs.maxReferenceDurationMs &&
               lhs.minDelayMs == rhs.minDelayMs &&
               lhs.maxDelayMs == rhs.maxDelayMs
    }
}

