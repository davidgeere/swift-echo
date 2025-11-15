// AudioLevel.swift
// Echo - Audio
// Audio level calculation for visualizations

import Foundation
import AVFoundation

/// Calculates audio levels for visualization purposes
public struct AudioLevel {
    // MARK: - Level Calculation

    /// Calculates the RMS (Root Mean Square) audio level from PCM16 audio data
    /// - Parameter data: PCM16 audio data (16-bit signed integers)
    /// - Returns: Audio level from 0.0 (silence) to 1.0 (maximum)
    public static func calculate(from data: Data) -> Double {
        guard !data.isEmpty else { return 0.0 }

        // PCM16 is 16-bit signed integers
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return 0.0 }

        var samples = [Int16](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { pointer in
            data.copyBytes(to: pointer)
        }

        // Calculate RMS
        var sum: Double = 0.0
        for sample in samples {
            let normalized = Double(sample) / Double(Int16.max)
            sum += normalized * normalized
        }

        let rms = sqrt(sum / Double(sampleCount))

        // Apply scaling and clamping
        let scaled = min(rms * 2.0, 1.0)  // Scale up for better visual range
        return scaled
    }

    /// Calculates the peak audio level from PCM16 audio data
    /// - Parameter data: PCM16 audio data
    /// - Returns: Peak level from 0.0 to 1.0
    public static func calculatePeak(from data: Data) -> Double {
        guard !data.isEmpty else { return 0.0 }

        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return 0.0 }

        var samples = [Int16](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { pointer in
            data.copyBytes(to: pointer)
        }

        let maxSample = samples.map(abs).max() ?? 0
        return Double(maxSample) / Double(Int16.max)
    }

    /// Calculates audio level from an AVAudioPCMBuffer
    /// - Parameter buffer: The audio buffer
    /// - Returns: Audio level from 0.0 to 1.0
    public static func calculate(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.int16ChannelData else { return 0.0 }
        guard buffer.frameLength > 0 else { return 0.0 }

        let frameCount = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)

        var sum: Double = 0.0
        for sample in samples {
            let normalized = Double(sample) / Double(Int16.max)
            sum += normalized * normalized
        }

        let rms = sqrt(sum / Double(frameCount))
        let scaled = min(rms * 2.0, 1.0)
        return scaled
    }

    // MARK: - Smoothing

    /// Smooths audio levels over time using exponential moving average
    public actor Smoother {
        private var currentLevel: Double = 0.0
        private let smoothingFactor: Double

        /// Creates a level smoother
        /// - Parameter smoothingFactor: 0.0-1.0, higher = more smoothing (default: 0.3)
        public init(smoothingFactor: Double = 0.3) {
            self.smoothingFactor = min(max(smoothingFactor, 0.0), 1.0)
        }

        /// Updates the smoothed level with a new measurement
        /// - Parameter newLevel: The new audio level
        /// - Returns: The smoothed level
        public func update(with newLevel: Double) -> Double {
            currentLevel = (smoothingFactor * currentLevel) + ((1.0 - smoothingFactor) * newLevel)
            return currentLevel
        }

        /// Resets the smoother to zero
        public func reset() {
            currentLevel = 0.0
        }

        /// Gets the current smoothed level without updating
        public var level: Double {
            return currentLevel
        }
    }

    // MARK: - Scaling

    /// Scales an audio level for better visualization
    /// - Parameters:
    ///   - level: The raw audio level (0.0-1.0)
    ///   - mode: The scaling mode to use
    /// - Returns: Scaled level (0.0-1.0)
    public static func scale(_ level: Double, mode: ScalingMode = .logarithmic) -> Double {
        let clamped = min(max(level, 0.0), 1.0)

        switch mode {
        case .linear:
            return clamped

        case .logarithmic:
            // Logarithmic scaling for more natural perception
            if clamped < 0.001 { return 0.0 }
            let db = 20 * log10(clamped)  // Convert to dB
            let normalizedDb = (db + 60) / 60  // Normalize -60dB to 0dB range
            return min(max(normalizedDb, 0.0), 1.0)

        case .exponential:
            return pow(clamped, 2.0)
        }
    }

    /// Scaling modes for audio level visualization
    public enum ScalingMode {
        /// Linear scaling (no transformation)
        case linear

        /// Logarithmic scaling (more natural perception)
        case logarithmic

        /// Exponential scaling (emphasizes louder sounds)
        case exponential
    }
}
