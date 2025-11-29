// AudioLifecycleEventTests.swift
// EchoTests
//
// Tests for audio lifecycle events (audioStarting, audioStarted, audioStopped)
//

import Testing
import Foundation
@testable import Echo

/// Test state for tracking audio lifecycle events
actor AudioLifecycleTestState {
    var audioStartingReceived = false
    var audioStartedReceived = false
    var audioStoppedReceived = false
    var eventOrder: [EventType] = []
    
    func reset() {
        audioStartingReceived = false
        audioStartedReceived = false
        audioStoppedReceived = false
        eventOrder = []
    }
    
    func recordEvent(_ eventType: EventType) {
        switch eventType {
        case .audioStarting:
            audioStartingReceived = true
        case .audioStarted:
            audioStartedReceived = true
        case .audioStopped:
            audioStoppedReceived = true
        default:
            break
        }
        eventOrder.append(eventType)
    }
}

@Suite("Audio Lifecycle Events")
struct AudioLifecycleEventTests {
    
    @Test("audioStarting is emitted when startAudio() begins")
    func testAudioStartingEvent() async throws {
        let emitter = EventEmitter()
        let state = AudioLifecycleTestState()
        
        // Use events stream to observe audioStarting
        let eventTask = Task {
            for await event in emitter.events {
                if case .audioStarting = event {
                    await state.recordEvent(.audioStarting)
                    break
                }
            }
        }
        
        // Create RealtimeClient with mock audio factories
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            instructions: nil,
            enableTranscription: false,
            startAudioAutomatically: false,
            temperature: 0.8,
            maxOutputTokens: nil
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioCaptureFactory: { MockAudioCapture() },
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        // Start audio - should emit audioStarting
        try await client.startAudio()
        
        // Wait for event processing
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        
        // Verify audioStarting was received
        let startingReceived = await state.audioStartingReceived
        #expect(startingReceived == true)
    }
    
    @Test("audioStarted is emitted after both capture and playback are ready")
    func testAudioStartedEvent() async throws {
        let emitter = EventEmitter()
        let state = AudioLifecycleTestState()
        
        // Use events stream to observe audio lifecycle events
        let eventTask = Task {
            for await event in emitter.events {
                switch event {
                case .audioStarting:
                    await state.recordEvent(.audioStarting)
                case .audioStarted:
                    await state.recordEvent(.audioStarted)
                default:
                    break
                }
                // Stop after audioStarted
                if await state.audioStartedReceived { break }
            }
        }
        
        // Create RealtimeClient with mock audio factories
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            instructions: nil,
            enableTranscription: false,
            startAudioAutomatically: false,
            temperature: 0.8,
            maxOutputTokens: nil
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioCaptureFactory: { MockAudioCapture() },
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        // Start audio - should emit audioStarting then audioStarted
        try await client.startAudio()
        
        // Wait for event processing
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        
        // Verify both events were received
        let startingReceived = await state.audioStartingReceived
        let startedReceived = await state.audioStartedReceived
        let eventOrder = await state.eventOrder
        
        #expect(startingReceived == true)
        #expect(startedReceived == true)
        
        // Verify correct order: audioStarting before audioStarted
        #expect(eventOrder.first == .audioStarting)
        #expect(eventOrder.contains(.audioStarted))
    }
    
    @Test("audioStopped is emitted when stopAudio() is called")
    func testAudioStoppedEventOnStop() async throws {
        let emitter = EventEmitter()
        let state = AudioLifecycleTestState()
        
        // Use events stream to observe audio lifecycle events
        let eventTask = Task {
            for await event in emitter.events {
                switch event {
                case .audioStarting:
                    await state.recordEvent(.audioStarting)
                case .audioStarted:
                    await state.recordEvent(.audioStarted)
                case .audioStopped:
                    await state.recordEvent(.audioStopped)
                default:
                    break
                }
                // Stop after audioStopped
                if await state.audioStoppedReceived { break }
            }
        }
        
        // Create RealtimeClient with mock audio factories
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            instructions: nil,
            enableTranscription: false,
            startAudioAutomatically: false,
            temperature: 0.8,
            maxOutputTokens: nil
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioCaptureFactory: { MockAudioCapture() },
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        // Start audio
        try await client.startAudio()
        
        // Small delay to ensure events are processed
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Stop audio - should emit audioStopped
        await client.stopAudio()
        
        // Wait for event processing
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        
        // Verify all events were received in correct order
        let startingReceived = await state.audioStartingReceived
        let startedReceived = await state.audioStartedReceived
        let stoppedReceived = await state.audioStoppedReceived
        let eventOrder = await state.eventOrder
        
        #expect(startingReceived == true)
        #expect(startedReceived == true)
        #expect(stoppedReceived == true)
        
        // Verify correct order: audioStarting -> audioStarted -> audioStopped
        #expect(eventOrder.first == .audioStarting)
        #expect(eventOrder.last == .audioStopped)
    }
    
    @Test("audioStopped is NOT emitted if audio was never started")
    func testAudioStoppedNotEmittedIfNeverStarted() async throws {
        let emitter = EventEmitter()
        let state = AudioLifecycleTestState()
        
        // Use events stream to observe audioStopped
        let eventTask = Task {
            for await event in emitter.events {
                if case .audioStopped = event {
                    await state.recordEvent(.audioStopped)
                    break
                }
            }
        }
        
        // Create RealtimeClient with mock audio factories
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            instructions: nil,
            enableTranscription: false,
            startAudioAutomatically: false,
            temperature: 0.8,
            maxOutputTokens: nil
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioCaptureFactory: { MockAudioCapture() },
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        // Stop audio without starting it - should NOT emit audioStopped
        await client.stopAudio()
        
        // Small delay to ensure events would be processed
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        
        // Verify audioStopped was NOT received
        let stoppedReceived = await state.audioStoppedReceived
        #expect(stoppedReceived == false)
    }
    
    @Test("audioStopped is emitted when startAudio() fails")
    func testAudioStoppedOnStartFailure() async throws {
        let emitter = EventEmitter()
        let state = AudioLifecycleTestState()
        
        // Use events stream to observe audio lifecycle events
        let eventTask = Task {
            for await event in emitter.events {
                switch event {
                case .audioStarting:
                    await state.recordEvent(.audioStarting)
                case .audioStarted:
                    await state.recordEvent(.audioStarted)
                case .audioStopped:
                    await state.recordEvent(.audioStopped)
                default:
                    break
                }
                // Stop after audioStopped (failure case)
                if await state.audioStoppedReceived { break }
            }
        }
        
        // Create a mock audio capture that throws an error
        actor FailingMockAudioCapture: AudioCaptureProtocol {
            let audioLevelStream: AsyncStream<Double>
            private let levelContinuation: AsyncStream<Double>.Continuation
            var isActive: Bool = false
            
            init() {
                var continuation: AsyncStream<Double>.Continuation?
                audioLevelStream = AsyncStream { cont in
                    continuation = cont
                }
                levelContinuation = continuation!
            }
            
            func start(onAudioChunk: @escaping @Sendable (String) async -> Void) async throws {
                throw RealtimeError.audioCaptureFailed(
                    NSError(domain: "Test", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Mock failure"
                    ])
                )
            }
            
            func stop() async {}
            func pause() async {}
            func resume() async throws {}
        }
        
        // Create RealtimeClient with failing mock audio capture
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            instructions: nil,
            enableTranscription: false,
            startAudioAutomatically: false,
            temperature: 0.8,
            maxOutputTokens: nil
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioCaptureFactory: { FailingMockAudioCapture() },
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        // Start audio - should fail and emit audioStopped
        do {
            try await client.startAudio()
            Issue.record("Expected startAudio() to throw")
        } catch {
            // Expected to throw
        }
        
        // Wait for event processing
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        
        // Verify audioStarting was received
        let startingReceived = await state.audioStartingReceived
        #expect(startingReceived == true)
        
        // Verify audioStarted was NOT received (setup failed)
        let startedReceived = await state.audioStartedReceived
        #expect(startedReceived == false)
        
        // Verify audioStopped WAS received (failure case)
        let stoppedReceived = await state.audioStoppedReceived
        #expect(stoppedReceived == true)
        
        // Verify correct order: audioStarting -> audioStopped (no audioStarted)
        let eventOrder = await state.eventOrder
        #expect(eventOrder.first == .audioStarting)
        #expect(eventOrder.contains(.audioStopped))
        #expect(!eventOrder.contains(.audioStarted))
    }
    
    @Test("Complete audio lifecycle event sequence")
    func testCompleteAudioLifecycleSequence() async throws {
        let emitter = EventEmitter()
        let state = AudioLifecycleTestState()
        
        // Use events stream to observe all audio lifecycle events
        let eventTask = Task {
            for await event in emitter.events {
                switch event {
                case .audioStarting:
                    await state.recordEvent(.audioStarting)
                case .audioStarted:
                    await state.recordEvent(.audioStarted)
                case .audioStopped:
                    await state.recordEvent(.audioStopped)
                default:
                    break
                }
                // Stop after audioStopped
                if await state.audioStoppedReceived { break }
            }
        }
        
        // Create RealtimeClient with mock audio factories
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            instructions: nil,
            enableTranscription: false,
            startAudioAutomatically: false,
            temperature: 0.8,
            maxOutputTokens: nil
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioCaptureFactory: { MockAudioCapture() },
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        // Complete lifecycle: start -> stop
        try await client.startAudio()
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await client.stopAudio()
        
        // Wait for event processing
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        
        // Verify all events were received
        let startingReceived = await state.audioStartingReceived
        let startedReceived = await state.audioStartedReceived
        let stoppedReceived = await state.audioStoppedReceived
        let eventOrder = await state.eventOrder
        
        #expect(startingReceived == true)
        #expect(startedReceived == true)
        #expect(stoppedReceived == true)
        
        // Verify correct sequence: audioStarting -> audioStarted -> audioStopped
        #expect(eventOrder.count == 3)
        #expect(eventOrder[0] == .audioStarting)
        #expect(eventOrder[1] == .audioStarted)
        #expect(eventOrder[2] == .audioStopped)
    }
}
