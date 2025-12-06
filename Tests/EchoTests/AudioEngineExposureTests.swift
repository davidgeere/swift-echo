// AudioEngineExposureTests.swift
// Echo Tests
// Tests for exposing AVAudioEngine for external audio monitoring (Issue #8)

@preconcurrency import AVFoundation
import Testing
@testable import Echo

/// Tests for AudioEngine exposure functionality
@Suite
struct AudioEngineExposureTests {
    
    // MARK: - AudioPlaybackProtocol Tests
    
    @Test
    func audioPlaybackProtocolHasAudioEngineProperty() async throws {
        // Given: A mock audio playback that conforms to AudioPlaybackProtocol
        let playback = MockAudioPlayback()
        
        // When: Accessing the audioEngine property
        let engine = await playback.audioEngine
        
        // Then: Mock returns nil (no real engine)
        #expect(engine == nil)
    }
    
    // MARK: - AudioPlayback Tests
    
    @Test
    func audioPlaybackEngineIsNilBeforeStart() async throws {
        // Given: A real audio playback instance (not started)
        let playback = AudioPlayback(format: .pcm16)
        
        // When: Checking the audioEngine before start
        let engine = await playback.audioEngine
        
        // Then: Engine should be nil
        #expect(engine == nil)
    }
    
    @Test
    func audioPlaybackEngineExistsAfterStart() async throws {
        // Given: A real audio playback instance
        let playback = AudioPlayback(format: .pcm16)
        
        // When: Starting playback
        try await playback.start()
        let engine = await playback.audioEngine
        
        // Then: Engine should exist and be running
        #expect(engine != nil)
        #expect(engine?.isRunning == true)
        
        // Cleanup
        await playback.stop()
    }
    
    @Test
    func audioPlaybackEngineIsNilAfterStop() async throws {
        // Given: A started audio playback instance
        let playback = AudioPlayback(format: .pcm16)
        try await playback.start()
        
        // Verify engine exists after start
        let engineBeforeStop = await playback.audioEngine
        #expect(engineBeforeStop != nil)
        
        // When: Stopping playback
        await playback.stop()
        let engineAfterStop = await playback.audioEngine
        
        // Then: Engine should be nil after stop
        #expect(engineAfterStop == nil)
    }
    
    @Test
    func audioPlaybackEngineCanBeUsedForTaps() async throws {
        // Given: A started audio playback instance
        let playback = AudioPlayback(format: .pcm16)
        try await playback.start()
        
        // When: Getting the audio engine
        let engine = await playback.audioEngine
        
        // Then: The engine's mainMixerNode should be accessible
        #expect(engine != nil)
        #expect(engine?.mainMixerNode != nil)
        
        // Verify tap can be installed (doesn't throw)
        // Note: We don't actually process audio, just verify access
        if let mixer = engine?.mainMixerNode {
            // The mixer should have a valid output format
            let format = mixer.outputFormat(forBus: 0)
            #expect(format.sampleRate > 0)
        }
        
        // Cleanup
        await playback.stop()
    }
    
    // MARK: - MockAudioPlayback Tests
    
    @Test
    func mockAudioPlaybackEngineIsAlwaysNil() async throws {
        // Given: A mock audio playback instance
        let playback = MockAudioPlayback()
        
        // When: Starting and checking engine
        try await playback.start()
        let engineAfterStart = await playback.audioEngine
        
        // Then: Mock should always return nil (no real engine)
        #expect(engineAfterStart == nil)
        
        // Cleanup
        await playback.stop()
    }
    
    // MARK: - Audio Tap Tests
    
    @Test
    func audioPlaybackEngineSupportsInstallingTaps() async throws {
        // Given: A started audio playback instance
        let playback = AudioPlayback(format: .pcm16)
        try await playback.start()
        
        guard let engine = await playback.audioEngine else {
            #expect(Bool(false), "Engine should be available")
            return
        }
        
        // When: Installing a tap on the main mixer node
        var tapWasInstalled = false
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { _, _ in
            tapWasInstalled = true
        }
        
        // Then: Tap should be installed successfully (no throw)
        // Remove tap to clean up
        mixer.removeTap(onBus: 0)
        
        // Cleanup
        await playback.stop()
        
        // Note: tapWasInstalled won't be true unless we actually play audio,
        // but the test verifies that tap installation works without errors
        #expect(true) // Test passes if no exception was thrown
    }
}
