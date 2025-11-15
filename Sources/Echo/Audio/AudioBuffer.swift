// AudioBuffer.swift
// Echo - Audio
// Thread-safe audio data buffering for streaming

import Foundation

/// Thread-safe buffer for accumulating and managing audio data
public actor AudioBuffer {
    // MARK: - Properties

    private var buffer: Data
    private let format: AudioFormat
    private let maxSize: Int

    /// Current size of buffered data in bytes
    public var size: Int {
        return buffer.count
    }

    /// Whether the buffer is empty
    public var isEmpty: Bool {
        return buffer.isEmpty
    }

    /// Current duration of buffered audio in seconds
    public var duration: TimeInterval {
        return format.duration(of: buffer)
    }

    /// Whether the buffer is full
    public var isFull: Bool {
        return buffer.count >= maxSize
    }

    // MARK: - Initialization

    /// Creates a new audio buffer
    /// - Parameters:
    ///   - format: The audio format for this buffer
    ///   - maxSize: Maximum buffer size in bytes (default: 5MB)
    public init(format: AudioFormat, maxSize: Int = 5_000_000) {
        self.format = format
        self.maxSize = maxSize
        self.buffer = Data()
        self.buffer.reserveCapacity(maxSize)
    }

    // MARK: - Buffer Operations

    /// Appends audio data to the buffer
    /// - Parameter data: The audio data to append
    /// - Throws: AudioBufferError if buffer would exceed max size
    public func append(_ data: Data) throws {
        guard buffer.count + data.count <= maxSize else {
            throw AudioBufferError.bufferOverflow(
                current: buffer.count,
                adding: data.count,
                max: maxSize
            )
        }

        guard format.validate(data: data) else {
            throw AudioBufferError.invalidData("Data does not conform to \(format) format")
        }

        buffer.append(data)
    }

    /// Reads and removes data from the buffer
    /// - Parameter count: Number of bytes to read, or nil for all data
    /// - Returns: The requested data
    public func read(count: Int? = nil) -> Data {
        if let count = count {
            let readCount = min(count, buffer.count)
            let data = buffer.prefix(readCount)
            buffer.removeFirst(readCount)
            return data
        } else {
            let data = buffer
            buffer.removeAll(keepingCapacity: true)
            return data
        }
    }

    /// Peeks at data without removing it from the buffer
    /// - Parameter count: Number of bytes to peek, or nil for all data
    /// - Returns: The requested data (still in buffer)
    public func peek(count: Int? = nil) -> Data {
        if let count = count {
            let peekCount = min(count, buffer.count)
            return buffer.prefix(peekCount)
        } else {
            return buffer
        }
    }

    /// Clears all data from the buffer
    public func clear() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// Reads a specific duration of audio from the buffer
    /// - Parameter duration: Duration in seconds
    /// - Returns: Audio data for the requested duration
    public func read(duration: TimeInterval) -> Data {
        let byteCount = format.dataSize(for: duration)
        return read(count: byteCount)
    }

    /// Checks if buffer contains at least the specified duration
    /// - Parameter duration: Duration in seconds
    /// - Returns: True if buffer has enough data
    public func hasData(forDuration duration: TimeInterval) -> Bool {
        let requiredBytes = format.dataSize(for: duration)
        return buffer.count >= requiredBytes
    }

    // MARK: - Chunking

    /// Reads audio in fixed-size chunks
    /// - Parameter chunkSize: Size of each chunk in bytes
    /// - Returns: AsyncStream of audio chunks
    public func chunks(ofSize chunkSize: Int) -> AsyncStream<Data> {
        return AsyncStream { continuation in
            Task {
                while !self.isEmpty {
                    let chunk = self.read(count: chunkSize)
                    if !chunk.isEmpty {
                        continuation.yield(chunk)
                    }

                    if chunk.count < chunkSize {
                        break  // No more full chunks available
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Reads audio in duration-based chunks
    /// - Parameter duration: Duration of each chunk in seconds
    /// - Returns: AsyncStream of audio chunks
    public func chunks(ofDuration duration: TimeInterval) -> AsyncStream<Data> {
        let chunkSize = format.dataSize(for: duration)
        return chunks(ofSize: chunkSize)
    }
}

// MARK: - Audio Buffer Errors

public enum AudioBufferError: Error, LocalizedError {
    case bufferOverflow(current: Int, adding: Int, max: Int)
    case invalidData(String)
    case insufficientData(required: Int, available: Int)

    public var errorDescription: String? {
        switch self {
        case .bufferOverflow(let current, let adding, let max):
            return "Buffer overflow: current=\(current), adding=\(adding), max=\(max)"
        case .invalidData(let reason):
            return "Invalid audio data: \(reason)"
        case .insufficientData(let required, let available):
            return "Insufficient data: required=\(required), available=\(available)"
        }
    }
}
