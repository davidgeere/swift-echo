// TurnDetection.swift
// Echo - Realtime API
// Turn detection configuration for managing conversation flow

import Foundation

/// Configuration for turn detection in the Realtime API
public enum TurnDetection: Sendable {
    /// Automatic turn detection using VAD
    case automatic(VADConfiguration)

    /// Manual turn detection - user controls when turns end
    /// - Parameter timeoutSeconds: Optional timeout in seconds for auto-advance (nil means no timeout)
    case manual(timeoutSeconds: Int? = nil)

    /// Disabled - no turn detection
    case disabled

    // MARK: - Presets

    /// Default automatic turn detection with balanced VAD settings
    public static let `default`: TurnDetection = .automatic(.default)

    /// Automatic turn detection optimized for quiet environments
    public static let quietEnvironment: TurnDetection = .automatic(.quiet)

    /// Automatic turn detection optimized for noisy environments
    public static let noisyEnvironment: TurnDetection = .automatic(.noisy)

    /// Automatic turn detection that waits longer for user to finish
    public static let patient: TurnDetection = .automatic(.patient)

    /// Automatic turn detection with faster response
    public static let responsive: TurnDetection = .automatic(.responsive)

    /// Automatic turn detection using semantic analysis
    public static let semantic: TurnDetection = .automatic(.semantic)

    // MARK: - Properties

    /// Whether turn detection is enabled
    public var isEnabled: Bool {
        switch self {
        case .automatic, .manual:
            return true
        case .disabled:
            return false
        }
    }

    /// The VAD configuration if using automatic detection
    public var vadConfiguration: VADConfiguration? {
        switch self {
        case .automatic(let config):
            return config
        case .manual, .disabled:
            return nil
        }
    }

    // MARK: - Conversion

    /// Converts to the format expected by the Realtime API
    public func toRealtimeFormat() -> [String: Any]? {
        switch self {
        case .automatic(let vadConfig):
            return [
                "type": vadConfig.type.rawValue,
                "threshold": vadConfig.threshold,
                "silence_duration_ms": vadConfig.silenceDurationMs,
                "prefix_padding_ms": vadConfig.prefixPaddingMs
            ]
        case .manual(let timeoutSeconds):
            // Manual mode: disable automatic VAD but keep session active
            return [
                "type": "server_vad",
                "threshold": 0.5,
                "silence_duration_ms": timeoutSeconds.map { $0 * 1000 } ?? Int.max,  // Convert to ms or never auto-detect
                "prefix_padding_ms": 300
            ]
        case .disabled:
            return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension TurnDetection: CustomStringConvertible {
    public var description: String {
        switch self {
        case .automatic(let config):
            return "Automatic turn detection: \(config)"
        case .manual(let timeoutSeconds):
            if let timeout = timeoutSeconds {
                return "Manual turn detection (timeout: \(timeout)s)"
            } else {
                return "Manual turn detection (no timeout)"
            }
        case .disabled:
            return "Turn detection disabled"
        }
    }
}
