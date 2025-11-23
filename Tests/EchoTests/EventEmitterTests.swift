// EventEmitterTests.swift
// EchoTests
//
// Comprehensive tests for EventEmitter and Echo event handling
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
    var handler1Called = false
    var handler2Called = false
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
        handler1Called = false
        handler2Called = false
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
    
    func setHandler1Called(_ value: Bool) {
        handler1Called = value
    }
    
    func setHandler2Called(_ value: Bool) {
        handler2Called = value
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

@Suite("Event Emitter")
struct EventEmitterTests {

    // MARK: - Single Event Handler Tests

    @Test("Single event handler receives event")
    func testSingleEventHandler() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userStartedSpeaking) { event in
            await state.setReceivedEvent(event)
        }
        
        await emitter.emit(.userStartedSpeaking)
        
        // Wait a moment for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let receivedEvent = await state.receivedEvent
        #expect(receivedEvent != nil)
        if case .userStartedSpeaking = receivedEvent! {
            // Correct event type
        } else {
            Issue.record("Expected .userStartedSpeaking event")
        }
    }

    @Test("Single event handler with associated value")
    func testSingleEventHandlerWithValue() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userTranscriptionCompleted) { event in
            guard case .userTranscriptionCompleted(let transcript, let itemId) = event else {
                return
            }
            await state.setReceivedTranscript(transcript)
            await state.setReceivedItemId(itemId)
        }
        
        await emitter.emit(.userTranscriptionCompleted(transcript: "Hello world", itemId: "item-123"))
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.receivedTranscript == "Hello world")
        #expect(await state.receivedItemId == "item-123")
    }

    @Test("Async event handler receives event")
    func testAsyncEventHandler() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.assistantStartedSpeaking) { event in
            // Simulate async work
            try? await Task.sleep(nanoseconds: 10_000_000)
            await state.setReceivedEvent(event)
        }
        
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for async handler execution
        try await Task.sleep(nanoseconds: 20_000_000)
        
        #expect(await state.receivedEvent != nil)
    }

    // MARK: - Multiple Events Array Syntax Tests

    @Test("Multiple events handler with array syntax receives all events")
    func testMultipleEventsArraySyntax() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when([.userStartedSpeaking, .assistantStartedSpeaking]) { event in
            switch event {
            case .userStartedSpeaking:
                await state.setEvent1Received(true)
            case .assistantStartedSpeaking:
                await state.setEvent2Received(true)
            default:
                break
            }
        }
        
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.event1Received)
        #expect(await state.event2Received)
    }

    @Test("Multiple events handler with array syntax handles three events")
    func testMultipleEventsArraySyntaxThreeEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when([.userStartedSpeaking, .userStoppedSpeaking, .assistantStartedSpeaking]) { event in
            await state.appendEvent(event.type)
        }
        
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.userStoppedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let events = await state.receivedEvents
        #expect(events.count == 3)
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.userStoppedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
    }

    @Test("Multiple events handler with array syntax extracts values correctly")
    func testMultipleEventsArraySyntaxWithValues() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when([.userTranscriptionCompleted, .assistantResponseDone]) { event in
            switch event {
            case .userTranscriptionCompleted(let transcript, _):
                await state.appendTranscript(transcript)
            case .assistantResponseDone(_, let text):
                await state.appendResponse(text)
            default:
                break
            }
        }
        
        await emitter.emit(.userTranscriptionCompleted(transcript: "Hello", itemId: "item-1"))
        await emitter.emit(.assistantResponseDone(itemId: "item-2", text: "Hi there"))
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let transcripts = await state.transcripts
        let responses = await state.responses
        #expect(transcripts.count == 1)
        #expect(transcripts[0] == "Hello")
        #expect(responses.count == 1)
        #expect(responses[0] == "Hi there")
    }

    // MARK: - Multiple Events Variadic Syntax Tests

    @Test("Multiple events handler with variadic syntax receives all events")
    func testMultipleEventsVariadicSyntax() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userStartedSpeaking, .assistantStartedSpeaking) { event in
            switch event {
            case .userStartedSpeaking:
                await state.setEvent1Received(true)
            case .assistantStartedSpeaking:
                await state.setEvent2Received(true)
            default:
                break
            }
        }
        
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.event1Received)
        #expect(await state.event2Received)
    }

    @Test("Multiple events handler with variadic syntax handles three events")
    func testMultipleEventsVariadicSyntaxThreeEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userStartedSpeaking, .userStoppedSpeaking, .assistantStartedSpeaking) { event in
            await state.appendEvent(event.type)
        }
        
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.userStoppedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let events = await state.receivedEvents
        #expect(events.count == 3)
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.userStoppedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
    }

    @Test("Multiple events handler with variadic syntax extracts values correctly")
    func testMultipleEventsVariadicSyntaxWithValues() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userTranscriptionCompleted, .assistantResponseDone) { event in
            switch event {
            case .userTranscriptionCompleted(let transcript, _):
                await state.appendTranscript(transcript)
            case .assistantResponseDone(_, let text):
                await state.appendResponse(text)
            default:
                break
            }
        }
        
        await emitter.emit(.userTranscriptionCompleted(transcript: "Hello", itemId: "item-1"))
        await emitter.emit(.assistantResponseDone(itemId: "item-2", text: "Hi there"))
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let transcripts = await state.transcripts
        let responses = await state.responses
        #expect(transcripts.count == 1)
        #expect(transcripts[0] == "Hello")
        #expect(responses.count == 1)
        #expect(responses[0] == "Hi there")
    }

    // MARK: - Echo.when() Tests

    @Test("Echo.when() single event works")
    func testEchoWhenSingleEvent() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        echo.when(.userStartedSpeaking) { event in
            Task {
                await state.setReceivedEvent(event)
            }
        }
        
        // Wait a moment for handler registration
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await echo.eventEmitter.emit(.userStartedSpeaking)
        
        // Wait a moment for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.receivedEvent != nil)
    }

    @Test("Echo.when() multiple events array syntax works")
    func testEchoWhenMultipleEventsArray() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        echo.when([.userStartedSpeaking, .assistantStartedSpeaking]) { event in
            Task {
                switch event {
                case .userStartedSpeaking:
                    await state.setEvent1Received(true)
                case .assistantStartedSpeaking:
                    await state.setEvent2Received(true)
                default:
                    break
                }
            }
        }
        
        // Wait for handler registration
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.event1Received)
        #expect(await state.event2Received)
    }

    @Test("Echo.when() multiple events variadic syntax works")
    func testEchoWhenMultipleEventsVariadic() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        echo.when(.userStartedSpeaking, .assistantStartedSpeaking) { event in
            Task {
                switch event {
                case .userStartedSpeaking:
                    await state.setEvent1Received(true)
                case .assistantStartedSpeaking:
                    await state.setEvent2Received(true)
                default:
                    break
                }
            }
        }
        
        // Wait for handler registration
        try await Task.sleep(nanoseconds: 10_000_000)
        
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.event1Received)
        #expect(await state.event2Received)
    }

    // MARK: - Multiple Handlers Tests

    @Test("Multiple handlers for same event all receive event")
    func testMultipleHandlersSameEvent() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userStartedSpeaking) { _ in
            await state.setHandler1Called(true)
        }
        
        await emitter.when(.userStartedSpeaking) { _ in
            await state.setHandler2Called(true)
        }
        
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        #expect(await state.handler1Called)
        #expect(await state.handler2Called)
    }

    @Test("Handler only receives events it's registered for")
    func testHandlerOnlyReceivesRegisteredEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userStartedSpeaking) { _ in
            await state.setHandlerCalled(true)
        }
        
        // Emit different event
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait a moment
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let handlerCalledBefore = await state.handlerCalled
        #expect(!handlerCalledBefore)
        
        // Emit correct event
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let handlerCalledAfter = await state.handlerCalled
        #expect(handlerCalledAfter)
    }

    // MARK: - Handler Removal Tests

    @Test("Handler can be removed by ID")
    func testRemoveHandlerById() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        let handlerId = await emitter.when(.userStartedSpeaking) { _ in
            await state.setHandlerCalled(true)
        }
        
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let handlerCalledBefore = await state.handlerCalled
        #expect(handlerCalledBefore)
        
        await state.reset()
        await emitter.removeHandler(handlerId)
        
        await emitter.emit(.userStartedSpeaking)
        
        // Wait a moment
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let handlerCalledAfter = await state.handlerCalled
        #expect(!handlerCalledAfter)
    }

    @Test("Removing handler doesn't affect other handlers")
    func testRemoveHandlerDoesntAffectOthers() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        let handler1Id = await emitter.when(.userStartedSpeaking) { _ in
            await state.setHandler1Called(true)
        }
        
        await emitter.when(.userStartedSpeaking) { _ in
            await state.setHandler2Called(true)
        }
        
        await emitter.removeHandler(handler1Id)
        
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let handler1Called = await state.handler1Called
        let handler2Called = await state.handler2Called
        #expect(!handler1Called)
        #expect(handler2Called)
    }

    // MARK: - Edge Cases

    @Test("Empty array of events doesn't crash")
    func testEmptyEventArray() async throws {
        let emitter = EventEmitter()
        
        // Should not crash
        let handlerIds = await emitter.when([], handler: { _ in })
        
        #expect(handlerIds.isEmpty)
    }

    @Test("Handler receives events in order")
    func testHandlerReceivesEventsInOrder() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        await emitter.when(.userStartedSpeaking, .userStoppedSpeaking) { event in
            await state.appendToOrder(event.type)
        }
        
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.userStoppedSpeaking)
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let order = await state.receivedOrder
        #expect(order.count == 3)
        #expect(order[0] == .userStartedSpeaking)
        #expect(order[1] == .userStoppedSpeaking)
        #expect(order[2] == .userStartedSpeaking)
    }

    // MARK: - All Events Handler Tests

    @Test("Echo.when() handler for all events receives events")
    func testEchoWhenAllEventsHandler() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Register handler for all events (async version - returns handler IDs)
        let handlerIds = await echo.when { event in
            await state.appendEvent(event.type)
        }
        
        // Should have handler IDs for all event types
        #expect(!handlerIds.isEmpty)
        
        // Emit various events
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStartedSpeaking)
        await echo.eventEmitter.emit(.audioLevelChanged(level: 0.5))
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.userStartedSpeaking))
        #expect(receivedEvents.contains(.assistantStartedSpeaking))
        #expect(receivedEvents.contains(.audioLevelChanged))
    }

    @Test("Echo.when() async handler for all events receives events")
    func testEchoWhenAllEventsAsyncHandler() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Register async handler for all events
        let handlerIds = await echo.when { event in
            await state.appendEvent(event.type)
        }
        
        // Should have handler IDs for all event types
        #expect(!handlerIds.isEmpty)
        
        // Emit various events
        await echo.eventEmitter.emit(.userStoppedSpeaking)
        await echo.eventEmitter.emit(.assistantStoppedSpeaking)
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.userStoppedSpeaking))
        #expect(receivedEvents.contains(.assistantStoppedSpeaking))
    }

    @Test("Echo.when() async handler for all events with async closure")
    func testEchoWhenAllEventsAsyncClosure() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Register async handler with async closure
        let handlerIds = await echo.when { event in
            await state.appendEvent(event.type)
            // Simulate async work
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        
        #expect(!handlerIds.isEmpty)
        
        await echo.eventEmitter.emit(.turnChanged(speaker: .user))
        
        // Wait for handler execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let receivedEvents = await state.receivedEvents
        #expect(receivedEvents.contains(.turnChanged))
    }

    @Test("Echo.events stream receives all events")
    func testEchoEventsStream() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume events from stream
        Task {
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
    }

    @Test("Echo.events stream can break out of loop")
    func testEchoEventsStreamCanBreak() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume events from stream with break condition
        Task {
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
    }
}
