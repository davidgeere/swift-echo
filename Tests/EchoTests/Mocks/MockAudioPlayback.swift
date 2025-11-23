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
    
    public func setSpeakerRouting(useSpeaker: Bool) async throws {
        // Mock implementation - no-op for testing
    }
}
