// AudioLevels.swift
// Echo - Audio
// Audio level measurements including overall amplitude and frequency bands

import Foundation

/// Represents audio level measurements including overall amplitude and frequency bands
///
/// All values are normalized to a 0.0-1.0 range for easy use in visualizations.
/// Frequency bands are extracted using FFT analysis:
/// - Low: 20-250 Hz (bass, rumble)
/// - Mid: 250-4000 Hz (voice, melody)
/// - High: 4000-20000 Hz (sibilance, air)
public struct AudioLevels: Sendable, Equatable {
    /// Overall RMS amplitude level (0.0-1.0)
    public var level: Float
    
    /// Low frequency band energy (20-250 Hz) - bass, rumble
    public var low: Float
    
    /// Mid frequency band energy (250-4000 Hz) - voice, melody
    public var mid: Float
    
    /// High frequency band energy (4000-20000 Hz) - sibilance, air
    public var high: Float
    
    /// Creates a new AudioLevels instance with specified values
    /// - Parameters:
    ///   - level: Overall RMS amplitude (0.0-1.0)
    ///   - low: Low frequency band energy (0.0-1.0)
    ///   - mid: Mid frequency band energy (0.0-1.0)
    ///   - high: High frequency band energy (0.0-1.0)
    public init(level: Float = 0, low: Float = 0, mid: Float = 0, high: Float = 0) {
        self.level = level
        self.low = low
        self.mid = mid
        self.high = high
    }
    
    /// An AudioLevels instance with all values set to zero
    public static let zero = AudioLevels()
    
    /// Returns a smoothed version of these levels transitioning from previous values
    /// - Parameters:
    ///   - previous: The previous audio levels
    ///   - factor: Smoothing factor (0.0-1.0, higher = faster response)
    /// - Returns: Smoothed audio levels
    public func smoothed(from previous: AudioLevels, factor: Float = 0.3) -> AudioLevels {
        AudioLevels(
            level: previous.level + (level - previous.level) * factor,
            low: previous.low + (low - previous.low) * factor,
            mid: previous.mid + (mid - previous.mid) * factor,
            high: previous.high + (high - previous.high) * factor
        )
    }
}

