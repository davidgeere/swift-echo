// EventEmitterTests.swift
// EchoTests
//
// Tests for EventEmitter v2.0 - Pure sink architecture
//

import Testing
import Foundation
@testable import Echo

/// Thread-safe test state holder
actor TestState {
    var receivedEvents: [EchoEvent] = []
    var receivedEventTypes: [EventType] = []
    var transcripts: [String] = []
    var responses: [String] = []
    
    func reset() {
        receivedEvents = []
        receivedEventTypes = []
        transcripts = []
        responses = []
    }
    
    func appendEvent(_ event: EchoEvent) {
        receivedEvents.append(event)
        receivedEventTypes.append(event.type)
    }
    
    func appendTranscript(_ transcript: String) {
        transcripts.append(transcript)
    }
    
    func appendResponse(_ response: String) {
        responses.append(response)
    }
}

@Suite("Event Emitter v2.0 - Pure Sink")
struct EventEmitterTests {

    // MARK: - Events Stream Tests

    @Test("Events stream receives emitted events")
    func testEventsStreamReceivesEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming from stream
        let consumeTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event)
                // Break after receiving 3 events
                if await state.receivedEvents.count >= 3 {
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        await emitter.emit(.audioLevelChanged(level: 0.5))
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // Cancel the task to stop the stream
        consumeTask.cancel()
        
        let events = await state.receivedEventTypes
        #expect(events.count >= 3)
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
        #expect(events.contains(.audioLevelChanged))
    }

    @Test("Events stream receives events with associated values")
    func testEventsStreamWithAssociatedValues() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming from stream
        let consumeTask = Task {
            for await event in emitter.events {
                switch event {
                case .userTranscriptionCompleted(let transcript, _):
                    await state.appendTranscript(transcript)
                case .assistantResponseDone(_, let text):
                    await state.appendResponse(text)
                default:
                    break
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
        
        // Emit events with values
        await emitter.emit(.userTranscriptionCompleted(transcript: "Hello world", itemId: "item-123"))
        await emitter.emit(.assistantResponseDone(itemId: "item-456", text: "Hi there!"))
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        consumeTask.cancel()
        
        let transcripts = await state.transcripts
        let responses = await state.responses
        #expect(transcripts.count >= 1)
        #expect(transcripts.first == "Hello world")
        #expect(responses.count >= 1)
        #expect(responses.first == "Hi there!")
    }

    @Test("Events stream can be cancelled")
    func testEventsStreamCanBeCancelled() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming from stream
        let consumeTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event)
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit one event
        await emitter.emit(.userStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Cancel the task
        consumeTask.cancel()
        
        // Emit another event after cancellation
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Should only have received the first event
        let events = await state.receivedEventTypes
        #expect(events.count == 1)
        #expect(events.first == .userStartedSpeaking)
    }

    @Test("Single consumer receives all events from stream")
    func testSingleConsumerReceivesAllEvents() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start a single consumer (AsyncStream supports single consumer pattern)
        let consumer = Task {
            for await event in emitter.events {
                await state.appendEvent(event)
                if await state.receivedEvents.count >= 2 { break }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        consumer.cancel()
        
        // Consumer should have received all events
        let events = await state.receivedEventTypes
        
        #expect(events.count >= 2)
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
    }

    @Test("Events are received in order")
    func testEventsReceivedInOrder() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming
        let consumeTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event)
                if await state.receivedEvents.count >= 4 { break }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events in order
        await emitter.emit(.userStartedSpeaking)
        await emitter.emit(.userStoppedSpeaking)
        await emitter.emit(.assistantStartedSpeaking)
        await emitter.emit(.assistantStoppedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        consumeTask.cancel()
        
        let events = await state.receivedEventTypes
        #expect(events.count >= 4)
        #expect(events[0] == .userStartedSpeaking)
        #expect(events[1] == .userStoppedSpeaking)
        #expect(events[2] == .assistantStartedSpeaking)
        #expect(events[3] == .assistantStoppedSpeaking)
    }

    @Test("emitAsync fires without waiting")
    func testEmitAsyncFiresWithoutWaiting() async throws {
        let emitter = EventEmitter()
        let state = TestState()
        
        // Start consuming
        let consumeTask = Task {
            for await event in emitter.events {
                await state.appendEvent(event)
                if await state.receivedEvents.count >= 1 { break }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Use nonisolated emitAsync
        emitter.emitAsync(.userStartedSpeaking)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        consumeTask.cancel()
        
        let events = await state.receivedEventTypes
        #expect(events.count >= 1)
        #expect(events.first == .userStartedSpeaking)
    }

    // MARK: - Echo Events Stream Tests

    @Test("Echo.events stream receives all events")
    func testEchoEventsStream() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume events from Echo's stream
        let consumeTask = Task {
            for await event in echo.events {
                await state.appendEvent(event)
                
                let count = await state.receivedEvents.count
                if count >= 3 { break }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Emit events through internal emitter
        await echo.eventEmitter.emit(.userStartedSpeaking)
        await echo.eventEmitter.emit(.assistantStartedSpeaking)
        await echo.eventEmitter.emit(.audioLevelChanged(level: 0.7))
        
        // Wait for stream processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        consumeTask.cancel()
        
        let events = await state.receivedEventTypes
        #expect(events.count >= 3)
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
        #expect(events.contains(.audioLevelChanged))
    }

    @Test("Echo.events stream can break on specific event")
    func testEchoEventsStreamCanBreak() async throws {
        let echo = Echo(key: "test-key")
        let state = TestState()
        
        // Consume with break condition
        let consumeTask = Task {
            for await event in echo.events {
                await state.appendEvent(event)
                
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
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        consumeTask.cancel()
        
        let events = await state.receivedEventTypes
        #expect(events.contains(.userStartedSpeaking))
        #expect(events.contains(.assistantStartedSpeaking))
        #expect(events.contains(.assistantStoppedSpeaking))
        // Should not contain userStoppedSpeaking because we broke before it
        #expect(!events.contains(.userStoppedSpeaking))
    }

    // MARK: - Tool Handler Tests

    @Test("Echo.toolHandler can be set")
    func testEchoToolHandlerCanBeSet() async throws {
        let echo = Echo(key: "test-key")
        
        // Initially nil
        #expect(echo.toolHandler == nil)
        
        // Set a handler
        echo.toolHandler = { toolCall in
            return "{\"result\": \"handled\"}"
        }
        
        // Now not nil
        #expect(echo.toolHandler != nil)
    }

    @Test("Echo.toolHandler receives tool call")
    func testEchoToolHandlerReceivesToolCall() async throws {
        let echo = Echo(key: "test-key")
        
        // Use actor for thread-safe state capture
        actor ToolCallCapture {
            var receivedToolCall: ToolCall?
            
            func capture(_ toolCall: ToolCall) {
                receivedToolCall = toolCall
            }
        }
        
        let capture = ToolCallCapture()
        
        echo.toolHandler = { toolCall in
            await capture.capture(toolCall)
            return "{\"result\": \"success\"}"
        }
        
        // Create a tool call
        let toolCall = ToolCall(
            id: "call-123",
            name: "test_tool",
            arguments: .object(["arg1": .string("value1")])
        )
        
        // Execute through the tool executor
        let result = await echo.toolExecutor.execute(toolCall: toolCall)
        
        // Wait for execution
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Handler should have received the call
        let receivedToolCall = await capture.receivedToolCall
        #expect(receivedToolCall != nil)
        #expect(receivedToolCall?.name == "test_tool")
        #expect(result.isSuccess)
    }
}


