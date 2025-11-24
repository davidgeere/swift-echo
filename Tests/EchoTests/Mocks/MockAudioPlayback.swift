// MockAudioPlayback.swift
// Echo Tests - Mocks
// Mock audio playback for headless testing without speaker hardware

import Foundation
@testable import Echo

/// Mock audio playback that simulates audio output without requiring speakers
/// Allows testing audio flows without requiring audio output permissions
public actor MockAudioPlayback: AudioPlaybackProtocol {
    private var isRunning = false
    private var queue: [String] = []
    private var currentOutput: AudioOutputDeviceType = .systemDefault
    
    public init() {}
    
    public func start() async throws {
        isRunning = true
    }
    
    public func stop() async {
        isRunning = false
        queue.removeAll()
    }
    
    public func enqueue(base64Audio: String) async throws {
        guard isRunning else { return }
        queue.append(base64Audio)
        
        // Simulate playback delay (20ms chunks)
        try? await Task.sleep(for: .milliseconds(20))
        
        if !queue.isEmpty {
            queue.removeFirst()
        }
    }
    
    public func interrupt() async {
        queue.removeAll()
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
}
