// EventEmitterTests.swift
// EchoTests
//
// Tests for the simplified EventEmitter (pure sink)
//

import Testing
import Foundation
@testable import Echo

/// Thread-safe test state holder
actor TestState {
    var receivedEvent: EchoEvent?
    var receivedTranscript: String?
    var receivedItemId: String?
    var receivedEvents: [EventType] = []
    var transcripts: [String] = []
    var responses: [String] = []
    var receivedOrder: [EventType] = []
    
    func reset() {
        receivedEvent = nil
        receivedTranscript = nil
        receivedItemId = nil
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

@Suite("Event Emitter (Pure Sink)")
struct EventEmitterTests {

    // MARK: - Basic Emission Tests

    @Test("Events stream receives emitted events")
    func testEventsStreamReceivesEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events
        let task = Task {
            for await event in emitter.events {
                await state.setReceivedEvent(event)
                break // Stop after first event
            }
        }
        
        // Give stream time to start
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let receivedEvent = await state.receivedEvent
        #expect(receivedEvent != nil)
        if let event = receivedEvent, case .userStartedSpeaking = event {
            // Correct event type
        } else {
            Issue.record("Expected .userStartedSpeaking event")
        }
        
        task.cancel()
    }

    @Test("Events stream receives events with associated values")
    func testEventsStreamWithAssociatedValues() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events
        let task = Task {
            for await event in emitter.events {
                if case .userTranscriptionCompleted(let transcript, let itemId) = event {
                    await state.setReceivedTranscript(transcript)
                    await state.setReceivedItemId(itemId)
                    break
                }
            }
        }
        
        // Give stream time to start
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await emitter.emit(.userTranscriptionCompleted(transcript: "Hello world", itemId: "item-123"))
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.receivedTranscript == "Hello world")
        #expect(await state.receivedItemId == "item-123")
        
        task.cancel()
    }

    @Test("Multiple events received in order")
    func testMultipleEventsInOrder() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events
        let task = Task {
            var count = 0
            for await event in emitter.events {
                await state.appendToOrder(event.type)
                count += 1
                if count >= 3 { break }
            }
        }
        
        // Give stream time to start
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.userStoppedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let order = await state.receivedOrder
        #expect(order.count == 3)
        #expect(order[0] == .userStartedSpeaking)
        #expect(order[1] == .userStoppedSpeaking)
        #expect(order[2] == .assistantStartedSpeaking)
        
        task.cancel()
    }

    // MARK: - Multiple Consumers Tests
    
    // Note: AsyncStream is single-consumer by design. Each consumer gets a subset of events.
    // For multiple consumers, the pattern is to have each consumer create their own observation task
    // from the same `events` stream, but events are distributed (not duplicated) between consumers.

    @Test("Events are consumed from stream")
    func testEventsConsumed() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Single consumer gets all events
        let task = Task {
            for await event in emitter.events {
                await state.appendEvent(event.type)
                if await state.receivedEvents.count >= 2 { break }
            }
        }
        
        // Give stream time to start
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let events = await state.receivedEvents
        
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
        #expect(events.count == 2)
        
        task.cancel()
    }

    // MARK: - Fire and Forget Tests

    @Test("emitAsync is fire and forget")
    func testEmitAsyncFireAndForget() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events
        let task = Task {
            for await event in emitter.events {
                await state.setReceivedEvent(event)
                break
            }
        }
        
        // Give stream time to start
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Use nonisolated emitAsync
        emitter.emitAsync(.userStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let receivedEvent = await state.receivedEvent
        #expect(receivedEvent != nil)
        
        task.cancel()
    }

    // MARK: - Echo Integration Tests

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
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.count >= 3)
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.audioLevelChanged))
        
        task.cancel()
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
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStoppedSpeaking))
        // Should not contain userStoppedSpeaking because we broke before it
        #expect(!receivedEvents.contains(.userStoppedSpeaking))
        
        task.cancel()
    }

    @Test("Events can be filtered using switch")
    func testEventsFiltering() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume only specific events
        let task = Task {
            for await event in echo.events {
                switch event {
                case .userTranscriptionCompleted(let transcript, _):
                    await state.appendTranscript(transcript)
                case .assistantResponseDone(_, let text):
                    await state.appendResponse(text)
                default:
                    break // Ignore other events
                }
                
                let transcriptCount = await state.transcripts.count
                let responseCount = await state.responses.count
                if transcriptCount >= 1 && responseCount >= 1 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit various events (some should be ignored)
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.userTranscriptionCompleted(transcript: "Hello", itemId: "item-1"))
        await echo.eventEmitter.emit(.assistantStartedSpeaking)
        await echo.eventEmitter.emit(.assistantResponseDone(itemId: "item-2", text: "Hi there"))
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let transcripts = await state.transcripts
        let responses = await state.responses
        #expect(transcripts.count == 1)
        #expect(transcripts[0] == "Hello")
        #expect(responses.count == 1)
        #expect(responses[0] == "Hi there")
        
        task.cancel()
    }

    @Test("Events stream with async where clause")
    func testEventsStreamWithWhereClause() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Filter events using where clause
        let task = Task {
            for await event in echo.events where event.type == .userStartedSpeaking || event.type == .userStoppedSpeaking {
                await state.appendEvent(event.type)
                
                let count = await state.receivedEvents.count
                if count >= 2 { break }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit various events (only user speech events should be captured)
        await echo.eventEmitter.emit(.assistantStartedSpeaking) // Should be ignored
        await echo.eventEmitter.emit(.userStartedSpeaking) // Should be captured
        await echo.eventEmitter.emit(.audioLevelChanged(level: 0.5)) // Should be ignored
        await echo.eventEmitter.emit(.userStoppedSpeaking) // Should be captured
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.count == 2)
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.userStoppedSpeaking))
        #expect(!receivedEvents.contains(.assistantStartedSpeaking))
        #expect(!receivedEvents.contains(.audioLevelChanged))
        
        task.cancel()
    }
}
