// AudioEncoder.swift

import Foundation
@preconcurrency import AVFoundation

/// Encodes audio data to various formats
public actor AudioEncoder {
    private let targetFormat: AudioFormat

    public init(targetFormat: AudioFormat) {
        self.targetFormat = targetFormat
    }

    /// Encode audio buffer to data
    public func encode(_ buffer: AVAudioPCMBuffer) throws -> Data {
        guard let channelData = buffer.int16ChannelData else {
            throw AudioEncoderError.invalidBufferFormat
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // For mono 16-bit PCM
        if channelCount == 1 {
            let data = Data(bytes: channelData[0], count: frameLength * 2)
            return data
        }

        // For multi-channel, interleave
        var data = Data(capacity: frameLength * channelCount * 2)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                var sampleCopy = sample
                data.append(Data(bytes: &sampleCopy, count: 2))
            }
        }

        return data
    }

    /// Encode audio data to base64 string
    public func encodeToBase64(_ buffer: AVAudioPCMBuffer) throws -> String {
        let data = try encode(buffer)
        return Base64Encoder.encode(data)
    }

    /// Encode PCM data with optional format conversion
    public func encode(_ data: Data, from sourceFormat: AudioFormat) throws -> Data {
        if sourceFormat == targetFormat {
            return data
        }

        // For now, return as-is. Full conversion would require AudioProcessor
        return data
    }
}

public enum AudioEncoderError: Error {
    case invalidBufferFormat
    case unsupportedConversion
    case encodingFailed(String)
}
