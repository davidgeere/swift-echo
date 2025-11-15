// AudioProcessor.swift
// Echo - Audio
// Audio format conversion and processing

import Foundation
@preconcurrency import AVFoundation

/// Processes and converts audio between different formats
public actor AudioProcessor {
    // MARK: - Properties

    private let targetFormat: AudioFormat
    private var converter: AVAudioConverter?

    // MARK: - Initialization

    /// Creates an audio processor
    /// - Parameter targetFormat: The target audio format for conversion
    public init(targetFormat: AudioFormat = .pcm16) {
        self.targetFormat = targetFormat
    }

    // MARK: - Format Conversion

    /// Converts an AVAudioPCMBuffer to the target format
    /// - Parameter buffer: The input audio buffer
    /// - Returns: Data in the target format
    /// - Throws: AudioProcessorError if conversion fails
    public func convert(_ buffer: AVAudioPCMBuffer) throws -> Data {
        guard let targetAVFormat = targetFormat.makeAVAudioFormat() else {
            throw AudioProcessorError.unsupportedFormat(targetFormat.rawValue)
        }

        let sourceFormat = buffer.format

        // If formats match, extract data directly
        if sourceFormat.sampleRate == targetAVFormat.sampleRate &&
           sourceFormat.commonFormat == targetAVFormat.commonFormat {
            return try extractData(from: buffer)
        }

        // Create converter if needed
        if converter == nil || converter?.inputFormat != sourceFormat {
            guard let newConverter = AVAudioConverter(from: sourceFormat, to: targetAVFormat) else {
                throw AudioProcessorError.converterCreationFailed
            }
            converter = newConverter
        }

        // Prepare output buffer
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (targetAVFormat.sampleRate / sourceFormat.sampleRate)
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetAVFormat,
            frameCapacity: capacity
        ) else {
            throw AudioProcessorError.bufferAllocationFailed
        }

        // Perform conversion
        var error: NSError?
        // Note: AVAudioPCMBuffer is not Sendable, but we're using it in a controlled manner
        nonisolated(unsafe) let capturedBuffer = buffer
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return capturedBuffer
        }

        let status = converter!.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if status == .error {
            throw AudioProcessorError.conversionFailed(error)
        }

        return try extractData(from: outputBuffer)
    }

    /// Converts raw audio data from one format to another
    /// - Parameters:
    ///   - data: The input audio data
    ///   - sourceFormat: The format of the input data
    /// - Returns: Data in the target format
    /// - Throws: AudioProcessorError if conversion fails
    public func convert(_ data: Data, from sourceFormat: AudioFormat) throws -> Data {
        guard let sourceAVFormat = sourceFormat.makeAVAudioFormat(),
              let _ = targetFormat.makeAVAudioFormat() else {
            throw AudioProcessorError.unsupportedFormat("Cannot convert between \(sourceFormat) and \(targetFormat)")
        }

        // Create buffer from data
        let frameCount = data.count / sourceFormat.bytesPerSample

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceAVFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw AudioProcessorError.bufferAllocationFailed
        }

        inputBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy data into buffer
        data.withUnsafeBytes { bytes in
            guard let src = bytes.baseAddress else { return }
            guard let dst = inputBuffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, data.count)
        }

        // Convert using existing method
        return try convert(inputBuffer)
    }

    // MARK: - Base64 Encoding

    /// Converts audio data to base64 string for WebSocket transmission
    /// - Parameter data: The audio data
    /// - Returns: Base64-encoded string
    public func toBase64(_ data: Data) -> String {
        return data.base64EncodedString()
    }

    /// Decodes base64 audio data from WebSocket
    /// - Parameter base64String: The base64-encoded audio
    /// - Returns: Decoded audio data
    /// - Throws: AudioProcessorError if decoding fails
    public func fromBase64(_ base64String: String) throws -> Data {
        guard let data = Data(base64Encoded: base64String) else {
            throw AudioProcessorError.base64DecodingFailed
        }
        return data
    }

    // MARK: - Buffer Chunking

    /// Splits audio data into fixed-size chunks
    /// - Parameters:
    ///   - data: The audio data
    ///   - chunkSize: Size of each chunk in bytes
    /// - Returns: Array of audio chunks
    public func chunk(_ data: Data, size chunkSize: Int) -> [Data] {
        var chunks: [Data] = []
        var offset = 0

        while offset < data.count {
            let remaining = data.count - offset
            let length = min(chunkSize, remaining)
            let chunk = data.subdata(in: offset..<(offset + length))
            chunks.append(chunk)
            offset += length
        }

        return chunks
    }

    /// Splits audio data into duration-based chunks
    /// - Parameters:
    ///   - data: The audio data
    ///   - duration: Duration of each chunk in seconds
    /// - Returns: Array of audio chunks
    public func chunk(_ data: Data, duration: TimeInterval) -> [Data] {
        let chunkSize = targetFormat.dataSize(for: duration)
        return chunk(data, size: chunkSize)
    }

    // MARK: - Private Helpers

    private func extractData(from buffer: AVAudioPCMBuffer) throws -> Data {
        guard let channelData = buffer.int16ChannelData else {
            throw AudioProcessorError.invalidBufferFormat
        }

        let frameCount = Int(buffer.frameLength)
        let dataSize = frameCount * MemoryLayout<Int16>.size

        var data = Data(count: dataSize)
        data.withUnsafeMutableBytes { bytes in
            guard let dst = bytes.baseAddress else { return }
            memcpy(dst, channelData[0], dataSize)
        }

        return data
    }
}

// MARK: - Audio Processor Errors

public enum AudioProcessorError: Error, LocalizedError {
    case unsupportedFormat(String)
    case converterCreationFailed
    case bufferAllocationFailed
    case conversionFailed(Error?)
    case invalidBufferFormat
    case base64DecodingFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .conversionFailed(let error):
            if let error = error {
                return "Audio conversion failed: \(error.localizedDescription)"
            }
            return "Audio conversion failed"
        case .invalidBufferFormat:
            return "Invalid audio buffer format"
        case .base64DecodingFailed:
            return "Failed to decode base64 audio data"
        }
    }
}
