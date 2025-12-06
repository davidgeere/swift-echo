// MockAudioPlayback.swift
// Echo Tests - Mocks
// Mock audio playback for headless testing without speaker hardware

import AVFoundation
import Foundation
@testable import Echo

/// Mock audio playback that simulates audio output without requiring speakers
/// Allows testing audio flows without requiring audio output permissions
public actor MockAudioPlayback: AudioPlaybackProtocol {
    private var isRunning = false
    private var queue: [String] = []
    private var currentOutput: AudioOutputDeviceType = .systemDefault
    private let levelContinuation: AsyncStream<AudioLevels>.Continuation
    
    public let audioLevelStream: AsyncStream<AudioLevels>
    
    public init() {
        var continuation: AsyncStream<AudioLevels>.Continuation?
        audioLevelStream = AsyncStream { cont in
            continuation = cont
        }
        levelContinuation = continuation!
    }
    
    public func start() async throws {
        isRunning = true
    }
    
    public func stop() async {
        isRunning = false
        queue.removeAll()
        levelContinuation.yield(.zero)
    }
    
    public func enqueue(base64Audio: String) async throws {
        guard isRunning else { return }
        queue.append(base64Audio)
        
        // Simulate playback and emit mock levels
        levelContinuation.yield(AudioLevels(level: 0.5, low: 0.3, mid: 0.5, high: 0.2))
        
        // Simulate playback delay (20ms chunks)
        try? await Task.sleep(for: .milliseconds(20))
        
        if !queue.isEmpty {
            queue.removeFirst()
        }
        
        // Reset levels after playback
        levelContinuation.yield(.zero)
    }
    
    public func interrupt() async {
        queue.removeAll()
        levelContinuation.yield(.zero)
    }
    
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        guard isRunning else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "MockAudioPlayback", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "Audio playback is not active"
                ])
            )
        }
        currentOutput = device
    }
    
    public var availableAudioOutputDevices: [AudioOutputDeviceType] {
        return [.builtInSpeaker, .builtInReceiver, .bluetooth(name: "Mock AirPods")]
    }
    
    public var currentAudioOutput: AudioOutputDeviceType {
        return currentOutput
    }
    
    public var isActive: Bool {
        return isRunning
    }
    
    /// Mock does not use a real AVAudioEngine
    public var audioEngine: AVAudioEngine? {
        return nil
    }
}
