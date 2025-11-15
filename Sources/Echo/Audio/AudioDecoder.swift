// AudioDecoder.swift

import Foundation
@preconcurrency import AVFoundation

/// Decodes audio data from various formats
public actor AudioDecoder {
    private let targetFormat: AudioFormat

    public init(targetFormat: AudioFormat) {
        self.targetFormat = targetFormat
    }

    /// Decode data to audio buffer
    public func decode(_ data: Data) throws -> AVAudioPCMBuffer {
        guard let avFormat = targetFormat.makeAVAudioFormat() else {
            throw AudioDecoderError.invalidFormat
        }

        let frameCount = data.count / (Int(avFormat.channelCount) * 2) // 2 bytes per sample for int16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw AudioDecoderError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.int16ChannelData else {
            throw AudioDecoderError.invalidBufferFormat
        }

        // Copy data to buffer
        data.withUnsafeBytes { rawBufferPointer in
            let int16Pointer = rawBufferPointer.bindMemory(to: Int16.self)

            if avFormat.channelCount == 1 {
                // Mono - direct copy
                for i in 0..<frameCount {
                    channelData[0][i] = int16Pointer[i]
                }
            } else {
                // Multi-channel - deinterleave
                let channelCount = Int(avFormat.channelCount)
                for frame in 0..<frameCount {
                    for channel in 0..<channelCount {
                        let index = frame * channelCount + channel
                        channelData[channel][frame] = int16Pointer[index]
                    }
                }
            }
        }

        return buffer
    }

    /// Decode base64 string to audio buffer
    public func decodeFromBase64(_ base64: String) throws -> AVAudioPCMBuffer {
        let data = try Base64Encoder.decode(base64)
        return try decode(data)
    }

    /// Decode with format conversion
    public func decode(_ data: Data, from sourceFormat: AudioFormat) throws -> AVAudioPCMBuffer {
        if sourceFormat == targetFormat {
            return try decode(data)
        }

        // For now, assume same format. Full conversion would require AudioProcessor
        return try decode(data)
    }
}

public enum AudioDecoderError: Error {
    case invalidFormat
    case invalidBufferFormat
    case bufferCreationFailed
    case decodingFailed(String)
}
