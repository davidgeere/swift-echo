// AudioFormat.swift
// Echo - Audio
// Audio format definitions for the Realtime API

import Foundation
import AVFoundation

/// Supported audio formats for the Realtime API
public enum AudioFormat: String, Sendable, CaseIterable {
    /// 16-bit PCM at 24kHz, mono
    case pcm16

    /// G.711 μ-law at 8kHz
    case g711ulaw = "g711_ulaw"

    /// G.711 A-law at 8kHz
    case g711alaw = "g711_alaw"

    // MARK: - Properties

    /// Sample rate in Hz
    public var sampleRate: Double {
        switch self {
        case .pcm16:
            return 24000  // 24kHz
        case .g711ulaw, .g711alaw:
            return 8000   // 8kHz
        }
    }

    /// Number of audio channels
    public var channels: Int {
        return 1  // All formats are mono
    }

    /// Bits per sample
    public var bitDepth: Int {
        switch self {
        case .pcm16:
            return 16
        case .g711ulaw, .g711alaw:
            return 8
        }
    }

    /// Bytes per sample
    public var bytesPerSample: Int {
        return bitDepth / 8
    }

    /// Whether this format uses compression
    public var isCompressed: Bool {
        switch self {
        case .pcm16:
            return false
        case .g711ulaw, .g711alaw:
            return true
        }
    }

    /// AVFoundation common format equivalent (for PCM16)
    public var avCommonFormat: AVAudioCommonFormat? {
        switch self {
        case .pcm16:
            return .pcmFormatInt16
        case .g711ulaw, .g711alaw:
            return nil  // G.711 requires custom handling
        }
    }

    /// User-friendly display name
    public var displayName: String {
        switch self {
        case .pcm16:
            return "PCM 16-bit (24kHz)"
        case .g711ulaw:
            return "G.711 μ-law (8kHz)"
        case .g711alaw:
            return "G.711 A-law (8kHz)"
        }
    }

    /// Brief description of the format
    public var description: String {
        switch self {
        case .pcm16:
            return "Uncompressed 16-bit PCM audio at 24kHz, mono. Best quality, higher bandwidth."
        case .g711ulaw:
            return "Compressed μ-law audio at 8kHz, mono. Lower quality, lower bandwidth."
        case .g711alaw:
            return "Compressed A-law audio at 8kHz, mono. Lower quality, lower bandwidth."
        }
    }

    /// Recommended format for best quality
    public static var recommended: AudioFormat {
        return .pcm16
    }

    /// Recommended format for low bandwidth
    public static var lowBandwidth: AudioFormat {
        return .g711ulaw
    }

    // MARK: - AVAudioFormat Creation

    /// Creates an AVAudioFormat for this audio format (if supported)
    /// - Returns: AVAudioFormat instance, or nil for G.711 formats
    public func makeAVAudioFormat() -> AVAudioFormat? {
        switch self {
        case .pcm16:
            return AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels),
                interleaved: true
            )
        case .g711ulaw, .g711alaw:
            // G.711 requires custom format description
            return nil
        }
    }

    // MARK: - Validation

    /// Validates that audio data conforms to this format's constraints
    /// - Parameter data: The audio data to validate
    /// - Returns: True if valid, false otherwise
    public func validate(data: Data) -> Bool {
        // Check that data length is a multiple of bytes per sample
        return data.count % bytesPerSample == 0
    }

    /// Calculates the duration of audio data in this format
    /// - Parameter data: The audio data
    /// - Returns: Duration in seconds
    public func duration(of data: Data) -> TimeInterval {
        let sampleCount = data.count / bytesPerSample
        return Double(sampleCount) / sampleRate
    }

    /// Calculates the expected data size for a given duration
    /// - Parameter duration: Duration in seconds
    /// - Returns: Expected size in bytes
    public func dataSize(for duration: TimeInterval) -> Int {
        let sampleCount = Int(duration * sampleRate)
        return sampleCount * bytesPerSample
    }
}

// MARK: - CustomStringConvertible

extension AudioFormat: CustomStringConvertible {
    public var debugDescription: String {
        return displayName
    }
}
