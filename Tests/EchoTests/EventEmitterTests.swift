// EventEmitterTests.swift
// EchoTests
//
// Comprehensive tests for EventEmitter (pure sink pattern)
//

import Testing
import Foundation
@testable import Echo

/// Thread-safe test state holder
actor TestState {
    var receivedEvent: EchoEvent?
    var receivedTranscript: String?
    var receivedItemId: String?
    var event1Received = false
    var event2Received = false
    var handlerCalled = false
    var receivedEvents: [EventType] = []
    var transcripts: [String] = []
    var responses: [String] = []
    var receivedOrder: [EventType] = []
    
    func reset() {
        receivedEvent = nil
        receivedTranscript = nil
        receivedItemId = nil
        event1Received = false
        event2Received = false
        handlerCalled = false
        receivedEvents = []
        transcripts = []
        responses = []
        receivedOrder = []
    }
    
    func appendEvent(_ eventType: EventType) {
        receivedEvents.append(eventType)
    }
    
    func appendTranscript(_ transcript: String) {
        transcripts.append(transcript)
    }
    
    func appendResponse(_ response: String) {
        responses.append(response)
    }
    
    func appendToOrder(_ eventType: EventType) {
        receivedOrder.append(eventType)
    }
    
    func setEvent1Received(_ value: Bool) {
        event1Received = value
    }
    
    func setEvent2Received(_ value: Bool) {
        event2Received = value
    }
    
    func setHandlerCalled(_ value: Bool) {
        handlerCalled = value
    }
    
    func setReceivedEvent(_ event: EchoEvent?) {
        receivedEvent = event
    }
    
    func setReceivedTranscript(_ transcript: String?) {
        receivedTranscript = transcript
    }
    
    func setReceivedItemId(_ itemId: String?) {
        receivedItemId = itemId
    }
}

@Suite("Event Emitter - Pure Sink Pattern")
struct EventEmitterTests {

    // MARK: - Stream Event Tests

    @Test("Events stream receives emitted events")
    func testEventsStreamReceivesEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream
        let task = Task {
            for await event in emitter.events {
                await state.setReceivedEvent(event)
                break // Only need first event
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit event
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let receivedEvent = await state.receivedEvent
        #expect(receivedEvent != nil)
        if case .userStartedSpeaking = receivedEvent! {
            // Correct event type
        } else {
            Issue.record("Expected .userStartedSpeaking event")
        }
    }

    @Test("Events stream receives event with associated value")
    func testEventsStreamWithAssociatedValue() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream
        let task = Task {
            for await event in emitter.events {
                if case .userTranscriptionCompleted(let transcript, let itemId) = event {
                    await state.setReceivedTranscript(transcript)
                    await state.setReceivedItemId(itemId)
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit event
        await emitter.emit(.userTranscriptionCompleted(transcript: "Hello world", itemId: "item-123"))
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        #expect(await state.receivedTranscript == "Hello world")
        #expect(await state.receivedItemId == "item-123")
    }

    @Test("Events stream receives multiple events in order")
    func testEventsStreamMultipleEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream
        let task = Task {
            var count = 0
            for await event in emitter.events {
                await state.appendEvent(event.type)
                count += 1
                if count >= 3 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit multiple events
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.userStoppedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let events = await state.receivedEvents
        #expect(events.count == 3)
        #expect(events[0] == .userStartedSpeaking)
        #expect(events[1] == .userStoppedSpeaking)
        #expect(events[2] == .assistantStartedSpeaking)
    }

    @Test("Events stream can break out of loop")
    func testEventsStreamCanBreak() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream with break condition
        let task = Task {
            for await event in emitter.events {
                await state.appendEvent(event.type)
                // Break on specific event
                if case .assistantStoppedSpeaking = event {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        await emitter.emit(.assistantStoppedSpeaking)
        await emitter.emit(.userStoppedSpeaking) // This should not be received
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStoppedSpeaking))
        // Should not contain userStoppedSpeaking because we broke before it
        #expect(!receivedEvents.contains(.userStoppedSpeaking))
    }

    @Test("AsyncStream distributes events among consumers")
    func testAsyncStreamDistributesEvents() async throws {
        // NOTE: AsyncStream only supports ONE consumer per stream.
        // Multiple consumers iterating the same stream will COMPETE for events,
        // not each receive all events. This is by design for the pure sink pattern.
        // If you need multiple observers, iterate the stream in one task and
        // dispatch to multiple handlers from there.
        
        let emitter = EventEmitter()
        let state = TestState()
        
        // Single consumer to verify events are received
        let task = Task {
            for await event in emitter.events {
                await state.appendEvent(event.type)
                if await state.receivedEvents.count >= 2 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let events = await state.receivedEvents
        
        // Single consumer should receive both events
        #expect(events.count >= 2)
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
    }

    // MARK: - Echo Events Stream Tests

    @Test("Echo.events stream receives all events")
    func testEchoEventsStream() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume events from stream
        let task = Task {
            for await event in echo.events {
                await state.appendEvent(event.type)
                
                // Break after receiving a few events
                let count = await state.receivedEvents.count
                if count >= 3 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStartedSpeaking)
        await echo.eventEmitter.emit(.audioLevelChanged(level: 0.7))
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.count >= 3)
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.audioLevelChanged))
    }

    @Test("Echo.events stream can break out of loop")
    func testEchoEventsStreamCanBreak() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume events from stream with break condition
        let task = Task {
            for await event in echo.events {
                await state.appendEvent(event.type)
                
                // Break on specific event
                if case .assistantStoppedSpeaking = event {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStoppedSpeaking)
        await echo.eventEmitter.emit(.userStoppedSpeaking) // This should not be received
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStoppedSpeaking))
        // Should not contain userStoppedSpeaking because we broke before it
        #expect(!receivedEvents.contains(.userStoppedSpeaking))
    }

    // MARK: - Event Filtering Tests

    @Test("Events can be filtered with switch statement")
    func testEventFiltering() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events and filter with switch
        let task = Task {
            for await event in emitter.events {
                switch event {
                case .userStartedSpeaking, .userStoppedSpeaking:
                    await state.appendEvent(event.type)
                case .assistantStoppedSpeaking:
                    break // Exit loop on this event
                default:
                    break // Ignore other events
                }
                
                // Check if we should exit
                if case .assistantStoppedSpeaking = event {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit various events
        await emitter.emit(.audioLevelChanged(level: 0.5)) // Should be ignored
        await emitter.emit(.userStartedSpeaking) // Should be captured
        await emitter.emit(.assistantStartedSpeaking) // Should be ignored
        await emitter.emit(.userStoppedSpeaking) // Should be captured
        await emitter.emit(.assistantStoppedSpeaking) // Should break loop
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.count == 2)
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.userStoppedSpeaking))
        #expect(!receivedEvents.contains(.assistantStartedSpeaking))
        #expect(!receivedEvents.contains(.audioLevelChanged))
    }

    // MARK: - EmitAsync Tests

    @Test("emitAsync fires event without waiting")
    func testEmitAsync() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream
        let task = Task {
            for await event in emitter.events {
                await state.setReceivedEvent(event)
                break
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit event using emitAsync (nonisolated)
        emitter.emitAsync(.userStartedSpeaking)
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        
        let receivedEvent = await state.receivedEvent
        #expect(receivedEvent != nil)
    }
}

// MARK: - Tool Handler Tests

@Suite("Echo Tool Handler")
struct EchoToolHandlerTests {
    
    @Test("toolHandler property can be set")
    func testToolHandlerPropertyCanBeSet() async throws {
        let echo = Echo(key: "test-key")
        
        // Initially nil
        #expect(echo.toolHandler == nil)
        
        // Set a handler
        echo.toolHandler = { toolCall in
            return "{\"result\": \"handled\"}"
        }
        
        // Now set
        #expect(echo.toolHandler != nil)
    }
    
    @Test("toolHandler can be cleared")
    func testToolHandlerCanBeCleared() async throws {
        let echo = Echo(key: "test-key")
        
        // Set a handler
        echo.toolHandler = { toolCall in
            return "{\"result\": \"handled\"}"
        }
        
        #expect(echo.toolHandler != nil)
        
        // Clear it
        echo.toolHandler = nil
        
        #expect(echo.toolHandler == nil)
    }
}
