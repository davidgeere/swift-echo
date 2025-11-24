// MockAudioCapture.swift
// Echo Tests - Mocks
// Mock audio capture for headless testing without microphone hardware

import Foundation
@testable import Echo

/// Mock audio capture that generates silent audio data for testing
/// Allows testing audio flows without requiring microphone permissions
public actor MockAudioCapture: AudioCaptureProtocol {
    private var isRunning = false
    private var captureTask: Task<Void, Never>?
    private let levelContinuation: AsyncStream<Double>.Continuation
    
    public let audioLevelStream: AsyncStream<Double>
    
    public init() {
        var continuation: AsyncStream<Double>.Continuation?
        audioLevelStream = AsyncStream { cont in
            continuation = cont
        }
        levelContinuation = continuation!
    }
    
    public func start(onAudioChunk: @escaping @Sendable (String) async -> Void) async throws {
        guard !isRunning else { return }
        isRunning = true
        
        // Generate mock audio data periodically (simulates 24kHz PCM16)
        captureTask = Task {
            while !Task.isCancelled && isRunning {
                // Silent PCM16 audio chunk (20ms at 24kHz = 960 samples = 1920 bytes)
                let silentAudio = Data(repeating: 0, count: 1920)
                let base64 = silentAudio.base64EncodedString()
                
                await onAudioChunk(base64)
                levelContinuation.yield(0.0)  // Silent level
                
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
    
    public func stop() async {
        isRunning = false
        captureTask?.cancel()
        captureTask = nil
    }
    
    public func pause() async {
        isRunning = false
    }
    
    public func resume() async throws {
        guard !isRunning else { return }
        isRunning = true
    }
    
    public var isActive: Bool {
        return isRunning
    }
}
