// ToolExecutorTests.swift
// EchoTests
//
// Tests for the centralized ToolExecutor

import Testing
import Foundation
@testable import Echo

@Suite("Tool Executor")
struct ToolExecutorTests {

    // MARK: - Registration Tests

    @Test("Tool can be registered")
    func testRegisterTool() async throws {
        let executor = ToolExecutor()
        
        let tool = Tool(
            name: "test_tool",
            description: "A test tool",
            parameters: ToolParameters(
                properties: [:],
                required: []
            )
        ) { _ in
            return "test output"
        }
        
        await executor.register(tool)
        
        let retrievedTool = await executor.getTool(named: "test_tool")
        #expect(retrievedTool != nil)
        #expect(retrievedTool?.name == "test_tool")
    }

    @Test("Multiple tools can be registered")
    func testRegisterMultipleTools() async throws {
        let executor = ToolExecutor()
        
        let tool1 = Tool(
            name: "tool_1",
            description: "Tool 1",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "output 1" }
        
        let tool2 = Tool(
            name: "tool_2",
            description: "Tool 2",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "output 2" }
        
        await executor.register([tool1, tool2])
        
        let names = await executor.registeredToolNames
        #expect(names.contains("tool_1"))
        #expect(names.contains("tool_2"))
    }

    @Test("Tool can be unregistered")
    func testUnregisterTool() async throws {
        let executor = ToolExecutor()
        
        let tool = Tool(
            name: "test_tool",
            description: "A test tool",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "output" }
        
        await executor.register(tool)
        
        // Verify registered
        var retrievedTool = await executor.getTool(named: "test_tool")
        #expect(retrievedTool != nil)
        
        // Unregister
        await executor.unregister(name: "test_tool")
        
        // Verify unregistered
        retrievedTool = await executor.getTool(named: "test_tool")
        #expect(retrievedTool == nil)
    }

    // MARK: - Execution Tests

    @Test("Registered tool executes successfully")
    func testExecuteRegisteredTool() async throws {
        let executor = ToolExecutor()
        
        let tool = Tool(
            name: "greet",
            description: "Greets a user",
            parameters: ToolParameters(
                properties: [
                    "name": .string(description: "Name to greet")
                ],
                required: ["name"]
            )
        ) { arguments in
            if let name = arguments["name"]?.value as? String {
                return "Hello, \(name)!"
            }
            return "Hello!"
        }
        
        await executor.register(tool)
        
        let toolCall = ToolCall(
            id: "call-123",
            name: "greet",
            arguments: .object(["name": .string("World")])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(result.isSuccess)
        #expect(result.output == "Hello, World!")
        #expect(result.toolCallId == "call-123")
    }

    @Test("Unregistered tool returns error")
    func testExecuteUnregisteredTool() async throws {
        let executor = ToolExecutor()
        
        let toolCall = ToolCall(
            id: "call-123",
            name: "unknown_tool",
            arguments: .object([:])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(!result.isSuccess)
        #expect(result.error != nil)
        #expect(result.error?.contains("not registered") == true)
    }

    @Test("Custom handler overrides automatic execution")
    func testCustomHandlerOverride() async throws {
        let executor = ToolExecutor()
        
        // Register a tool that would return "automatic"
        let tool = Tool(
            name: "test_tool",
            description: "Test",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "automatic" }
        
        await executor.register(tool)
        
        // Set custom handler that returns "custom"
        await executor.setCustomHandler { toolCall in
            return "custom: \(toolCall.name)"
        }
        
        let toolCall = ToolCall(
            id: "call-123",
            name: "test_tool",
            arguments: .object([:])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(result.isSuccess)
        #expect(result.output == "custom: test_tool")
    }

    @Test("Custom handler error is captured")
    func testCustomHandlerError() async throws {
        let executor = ToolExecutor()
        
        // Set custom handler that throws
        await executor.setCustomHandler { _ in
            throw NSError(domain: "TestError", code: 42, userInfo: [
                NSLocalizedDescriptionKey: "Custom handler failed"
            ])
        }
        
        let toolCall = ToolCall(
            id: "call-123",
            name: "any_tool",
            arguments: .object([:])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(!result.isSuccess)
        #expect(result.error != nil)
        #expect(result.error?.contains("Custom handler failed") == true)
    }

    @Test("Clearing custom handler reverts to automatic execution")
    func testClearCustomHandler() async throws {
        let executor = ToolExecutor()
        
        // Register a tool
        let tool = Tool(
            name: "test_tool",
            description: "Test",
            parameters: ToolParameters(properties: [:], required: [])
        ) { _ in "automatic" }
        
        await executor.register(tool)
        
        // Set then clear custom handler
        await executor.setCustomHandler { _ in "custom" }
        await executor.setCustomHandler(nil)
        
        let toolCall = ToolCall(
            id: "call-123",
            name: "test_tool",
            arguments: .object([:])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(result.isSuccess)
        #expect(result.output == "automatic")
    }

    @Test("Tool execution with complex arguments")
    func testToolExecutionWithComplexArguments() async throws {
        let executor = ToolExecutor()
        
        let tool = Tool(
            name: "calculate",
            description: "Calculate sum",
            parameters: ToolParameters(
                properties: [
                    "a": .number(description: "First number"),
                    "b": .number(description: "Second number")
                ],
                required: ["a", "b"]
            )
        ) { arguments in
            guard let a = arguments["a"]?.value as? Double,
                  let b = arguments["b"]?.value as? Double else {
                return "error: invalid arguments"
            }
            return "\(Int(a + b))"
        }
        
        await executor.register(tool)
        
        let toolCall = ToolCall(
            id: "call-123",
            name: "calculate",
            arguments: .object([
                "a": .number(10),
                "b": .number(20)
            ])
        )
        
        let result = await executor.execute(toolCall: toolCall)
        
        #expect(result.isSuccess)
        #expect(result.output == "30")
    }
}
