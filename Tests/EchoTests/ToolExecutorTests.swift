// ToolExecutorTests.swift
// EchoTests
//
// Tests for ToolExecutor - centralized tool execution

import Testing
import Foundation
@testable import Echo

@Suite("Tool Executor")
struct ToolExecutorTests {
    
    // MARK: - Registration Tests
    
    @Test("Can register a tool")
    func testRegisterTool() async throws {
        let emitter = EventEmitter()
        let executor = ToolExecutor(eventEmitter: emitter)
        
        let tool = Tool(
            name: "test_tool",
            description: "A test tool",
            parameters: ToolParameters(properties: [:]),
            handler: { _ in
                return "{}"
            }
        )
        
        await executor.register(tool)
        
        let registeredTool = await executor.getTool(named: "test_tool")
        #expect(registeredTool != nil)
        #expect(registeredTool?.name == "test_tool")
    }
    
    @Test("Can register multiple tools")
    func testRegisterMultipleTools() async throws {
        let emitter = EventEmitter()
        let executor = ToolExecutor(eventEmitter: emitter)
        
        let tool1 = Tool(
            name: "tool_one",
            description: "Tool one",
            parameters: ToolParameters(properties: [:]),
            handler: { _ in "{}" }
        )
        
        let tool2 = Tool(
            name: "tool_two",
            description: "Tool two",
            parameters: ToolParameters(properties: [:]),
            handler: { _ in "{}" }
        )
        
        await executor.register([tool1, tool2])
        
        let names = await executor.registeredToolNames
        #expect(names.count == 2)
        #expect(names.contains("tool_one"))
        #expect(names.contains("tool_two"))
    }
    
    @Test("Can unregister a tool")
    func testUnregisterTool() async throws {
        let emitter = EventEmitter()
        let executor = ToolExecutor(eventEmitter: emitter)
        
        let tool = Tool(
            name: "to_remove",
            description: "Will be removed",
            parameters: ToolParameters(properties: [:]),
            handler: { _ in "{}" }
        )
        
        await executor.register(tool)
        #expect(await executor.getTool(named: "to_remove") != nil)
        
        await executor.unregister(named: "to_remove")
        #expect(await executor.getTool(named: "to_remove") == nil)
    }
    
    // MARK: - Execution Tests
    
    @Test("Executes registered tool successfully")
    func testExecuteRegisteredTool() async throws {
        let emitter = EventEmitter()
        let executor = ToolExecutor(eventEmitter: emitter)
        
        let tool = Tool(
            name: "add",
            description: "Adds two numbers",
            parameters: ToolParameters(properties: [:]),
            handler: { args in
                return "{\"result\": 42}"
            }
        )
        
        await executor.register(tool)
        
        let toolCall = ToolCall(
            id: "call-123",
            name: "add",
            arguments: .object(["a": .number(20), "b": .number(22)])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(result.isSuccess)
        #expect(result.toolCallId == "call-123")
        #expect(result.output.contains("42"))
    }
    
    @Test("Returns error for unregistered tool")
    func testExecuteUnregisteredToolReturnsError() async throws {
        let emitter = EventEmitter()
        let executor = ToolExecutor(eventEmitter: emitter)
        
        let toolCall = ToolCall(
            id: "call-456",
            name: "nonexistent_tool",
            arguments: .object([:])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(!result.isSuccess)
        #expect(result.error != nil)
    }
    
    // MARK: - Custom Handler Tests
    
    @Test("Custom handler overrides automatic execution")
    func testCustomHandlerOverridesAutomatic() async throws {
        let emitter = EventEmitter()
        
        // Create a mock handler provider
        let mockProvider = MockToolHandlerProvider()
        mockProvider.customHandler = { toolCall in
            return "{\"custom\": \"handled\"}"
        }
        
        let executor = ToolExecutor(eventEmitter: emitter, customHandlerProvider: mockProvider)
        
        // Register a tool that would return different output
        let tool = Tool(
            name: "override_test",
            description: "Test override",
            parameters: ToolParameters(properties: [:]),
            handler: { _ in
                return "{\"automatic\": \"execution\"}"
            }
        )
        
        await executor.register(tool)
        
        let toolCall = ToolCall(
            id: "call-789",
            name: "override_test",
            arguments: .object([:])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        // Should get custom handler result, not automatic
        #expect(result.isSuccess)
        #expect(result.output.contains("custom"))
        #expect(!result.output.contains("automatic"))
    }
    
    @Test("Custom handler error is handled gracefully")
    func testCustomHandlerErrorHandling() async throws {
        let emitter = EventEmitter()
        
        let mockProvider = MockToolHandlerProvider()
        mockProvider.customHandler = { toolCall in
            throw TestError.intentionalFailure
        }
        
        let executor = ToolExecutor(eventEmitter: emitter, customHandlerProvider: mockProvider)
        
        let toolCall = ToolCall(
            id: "call-error",
            name: "error_test",
            arguments: .object([:])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(!result.isSuccess)
        #expect(result.error != nil)
    }
    
    // MARK: - Event Emission Tests
    
    @Test("Emits toolCallRequested event")
    func testEmitsToolCallRequestedEvent() async throws {
        let emitter = EventEmitter()
        let executor = ToolExecutor(eventEmitter: emitter)
        
        var receivedEvent: EchoEvent?
        
        // Listen for events
        let listenTask = Task {
            for await event in emitter.events {
                if case .toolCallRequested = event {
                    receivedEvent = event
                    break
                }
            }
        }
        
        // Wait for listener to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        let toolCall = ToolCall(
            id: "call-event",
            name: "event_test",
            arguments: .object([:])
        )
        
        _ = await executor.execute(toolCall: toolCall)
        
        // Wait for event processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        listenTask.cancel()
        
        #expect(receivedEvent != nil)
        if case .toolCallRequested(let call) = receivedEvent {
            #expect(call.name == "event_test")
        }
    }
    
    @Test("Emits toolResultSubmitted event")
    func testEmitsToolResultSubmittedEvent() async throws {
        let emitter = EventEmitter()
        let executor = ToolExecutor(eventEmitter: emitter)
        
        var receivedEvent: EchoEvent?
        
        // Listen for events
        let listenTask = Task {
            for await event in emitter.events {
                if case .toolResultSubmitted = event {
                    receivedEvent = event
                    break
                }
            }
        }
        
        // Wait for listener to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Register a tool so it succeeds
        let tool = Tool(
            name: "result_test",
            description: "Test result",
            parameters: ToolParameters(properties: [:]),
            handler: { _ in
                return "{\"done\": true}"
            }
        )
        await executor.register(tool)
        
        let toolCall = ToolCall(
            id: "call-result",
            name: "result_test",
            arguments: .object([:])  // Empty object instead of null
        )
        
        _ = await executor.execute(toolCall: toolCall)
        
        // Wait for event processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        listenTask.cancel()
        
        #expect(receivedEvent != nil)
        if case .toolResultSubmitted(let callId, let result) = receivedEvent {
            #expect(callId == "call-result")
            #expect(result.contains("done"))
        }
    }
}

// MARK: - Test Helpers

/// Mock tool handler provider for testing
final class MockToolHandlerProvider: ToolHandlerProvider, @unchecked Sendable {
    var customHandler: (@Sendable (ToolCall) async throws -> String)?
    
    var toolHandler: (@Sendable (ToolCall) async throws -> String)? {
        return customHandler
    }
}

/// Test error for intentional failures
enum TestError: Error {
    case intentionalFailure
}
