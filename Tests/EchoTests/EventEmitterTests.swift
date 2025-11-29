// EventEmitterTests.swift
// EchoTests
//
// Tests for the simplified EventEmitter (pure sink pattern)
//

import Testing
import Foundation
@testable import Echo

/// Thread-safe test state holder
actor TestState {
    var receivedEvents: [EventType] = []
    var transcripts: [String] = []
    var itemIds: [String] = []
    
    func reset() {
        receivedEvents = []
        transcripts = []
        itemIds = []
    }
    
    func appendEvent(_ eventType: EventType) {
        receivedEvents.append(eventType)
    }
    
    func appendTranscript(_ transcript: String) {
        transcripts.append(transcript)
    }
    
    func appendItemId(_ itemId: String) {
        itemIds.append(itemId)
    }
}

@Suite("Event Emitter - Pure Sink Pattern")
struct EventEmitterTests {

    // MARK: - Basic Emission Tests

    @Test("Events are yielded to the stream")
    func testEventsYieldedToStream() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream
        let eventTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event.type)
                
                // Break after receiving the event
                let count = await state.receivedEvents.count
                if count >= 1 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit event
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        eventTask.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.userStartedSpeaking))
    }

    @Test("Multiple events are received in order")
    func testMultipleEventsInOrder() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream
        let eventTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event.type)
                
                let count = await state.receivedEvents.count
                if count >= 3 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events in order
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.userStoppedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        eventTask.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.count == 3)
        #expect(receivedEvents[0] == .userStartedSpeaking)
        #expect(receivedEvents[1] == .userStoppedSpeaking)
        #expect(receivedEvents[2] == .assistantStartedSpeaking)
    }

    @Test("Events with associated values are received correctly")
    func testEventsWithAssociatedValues() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events from stream
        let eventTask = Task {
            for await event in emitter.events {
                switch event {
                case .userTranscriptionCompleted(let transcript, let itemId):
                    await state.appendTranscript(transcript)
                    await state.appendItemId(itemId)
                default:
                    break
                }
                
                let count = await state.transcripts.count
                if count >= 1 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit event with associated values
        await emitter.emit(.userTranscriptionCompleted(transcript: "Hello world", itemId: "item-123"))
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        eventTask.cancel()
        
        let transcripts = await state.transcripts
        let itemIds = await state.itemIds
        
        #expect(transcripts.count == 1)
        #expect(transcripts[0] == "Hello world")
        #expect(itemIds.count == 1)
        #expect(itemIds[0] == "item-123")
    }

    @Test("Multiple consumers receive events")
    func testMultipleConsumers() async throws {
        let emitter = EventEmitter()
        let state1 = TestState()
        let state2 = TestState()
        
        // Start two consumers
        let task1 = Task {
            for await event in emitter.events {
                await state1.appendEvent(event.type)
                let count = await state1.receivedEvents.count
                if count >= 2 {
                    break
                }
            }
        }
        
        let task2 = Task {
            for await event in emitter.events {
                await state2.appendEvent(event.type)
                let count = await state2.receivedEvents.count
                if count >= 2 {
                    break
                }
            }
        }
        
        // Wait for streams to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 100_000_000)
        
        task1.cancel()
        task2.cancel()
        
        // Both consumers should receive events
        let events1 = await state1.receivedEvents
        let events2 = await state2.receivedEvents
        
        #expect(events1.count >= 1)
        #expect(events2.count >= 1)
    }

    @Test("Stream can be cancelled")
    func testStreamCanBeCancelled() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events
        let eventTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event.type)
                
                // Cancel after first event
                return
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking) // This might not be received
        
        // Wait for task to complete
        await eventTask.value
        
        // Only first event should be received
        let events = await state.receivedEvents
        #expect(events.count == 1)
        #expect(events[0] == .userStartedSpeaking)
    }

    @Test("emitAsync fires asynchronously")
    func testEmitAsync() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming events
        let eventTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event.type)
                let count = await state.receivedEvents.count
                if count >= 1 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Use emitAsync (fire-and-forget)
        emitter.emitAsync(.userStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        eventTask.cancel()
        
        let events = await state.receivedEvents
        #expect(events.contains(.userStartedSpeaking))
    }

    // MARK: - Echo Events Stream Tests

    @Test("Echo.events stream receives all events")
    func testEchoEventsStream() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume events from stream
        let eventTask = Task {
            for await event in echo.events {
                await state.appendEvent(event.type)
                
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
        await echo.eventEmitter.emit(.audioLevelChanged(level: 0.5))
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        eventTask.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.count >= 3)
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.audioLevelChanged))
    }

    @Test("Echo.events stream can filter events with switch")
    func testEchoEventsStreamFiltering() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume only specific events
        let eventTask = Task {
            for await event in echo.events {
                switch event {
                case .userStartedSpeaking, .userStoppedSpeaking:
                    await state.appendEvent(event.type)
                default:
                    break  // Ignore other events
                }
                
                let count = await state.receivedEvents.count
                if count >= 2 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit various events
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStartedSpeaking)  // Should be ignored
        await echo.eventEmitter.emit(.userStoppedSpeaking)
        await echo.eventEmitter.emit(.audioLevelChanged(level: 0.5))  // Should be ignored
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        eventTask.cancel()
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.count == 2)
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.userStoppedSpeaking))
        #expect(!receivedEvents.contains(.assistantStartedSpeaking))
        #expect(!receivedEvents.contains(.audioLevelChanged))
    }

    @Test("Echo.events stream can break on specific event")
    func testEchoEventsStreamBreakCondition() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume events until a specific condition
        let eventTask = Task {
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
        await echo.eventEmitter.emit(.userStoppedSpeaking)  // Should not be received
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStoppedSpeaking))
        // userStoppedSpeaking might or might not be received depending on timing
    }
}
