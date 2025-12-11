// InputAudioConfiguration.swift
// Echo - Audio
// Configuration for input audio processing including noise reduction

import Foundation

/// Configuration for input audio processing on the server side
public struct InputAudioConfiguration: Sendable {
    // MARK: - Noise Reduction Types

    /// Type of server-side noise reduction to apply
    public enum NoiseReductionType: String, Sendable {
        /// Near-field noise reduction optimized for close microphone use
        /// Best for earpiece/receiver mode where device is close to face
        case nearField = "near_field"

        /// Far-field noise reduction optimized for speaker mode
        /// Better at handling echo and room noise when device is further away
        case farField = "far_field"
    }

    // MARK: - Properties

    /// Type of noise reduction to apply, or nil for no noise reduction
    public let noiseReductionType: NoiseReductionType?

    // MARK: - Initialization

    /// Creates an input audio configuration
    /// - Parameter noiseReductionType: The noise reduction type to use, or nil for none
    public init(noiseReductionType: NoiseReductionType? = .nearField) {
        self.noiseReductionType = noiseReductionType
    }

    // MARK: - Presets

    /// Near-field noise reduction for earpiece/receiver mode
    public static let nearField = InputAudioConfiguration(noiseReductionType: .nearField)

    /// Far-field noise reduction for speaker mode
    /// Better at handling echo from speaker output
    public static let farField = InputAudioConfiguration(noiseReductionType: .farField)

    /// No noise reduction
    public static let disabled = InputAudioConfiguration(noiseReductionType: nil)

    /// Speaker-optimized configuration using far-field noise reduction
    public static let speakerOptimized = InputAudioConfiguration(noiseReductionType: .farField)

    /// Earpiece-optimized configuration using near-field noise reduction
    public static let earpieceOptimized = InputAudioConfiguration(noiseReductionType: .nearField)

    // MARK: - Conversion

    /// Converts to the format expected by the Realtime API
    /// Returns nil if noise reduction is disabled
    public func toRealtimeFormat() -> [String: Any]? {
        guard let noiseReductionType = noiseReductionType else {
            return nil
        }

        return [
            "noise_reduction": [
                "type": noiseReductionType.rawValue
            ]
        ]
    }
}

// MARK: - CustomStringConvertible

extension InputAudioConfiguration: CustomStringConvertible {
    public var description: String {
        if let type = noiseReductionType {
            return "InputAudio(noiseReduction: \(type.rawValue))"
        } else {
            return "InputAudio(noiseReduction: disabled)"
        }
    }
}

// MARK: - Equatable

extension InputAudioConfiguration: Equatable {
    public static func == (lhs: InputAudioConfiguration, rhs: InputAudioConfiguration) -> Bool {
        return lhs.noiseReductionType == rhs.noiseReductionType
    }
}

