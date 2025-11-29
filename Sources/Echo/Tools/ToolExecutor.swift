// ToolExecutor.swift
// Echo - Tools
// Centralized tool execution, called directly by RealtimeClient

import Foundation

/// Centralized actor for tool execution
/// This replaces the event-based tool execution pattern
public actor ToolExecutor: ToolExecuting {
    // MARK: - Properties
    
    /// Registered tools by name
    private var tools: [String: Tool] = [:]
    
    /// Optional custom handler closure for manual tool handling
    private var customHandler: (@Sendable (ToolCall) async throws -> String)?
    
    // MARK: - Initialization
    
    /// Creates a new ToolExecutor
    public init() {
        // Default initialization
    }
    
    // MARK: - Tool Registration
    
    /// Registers a tool for automatic execution
    /// - Parameter tool: The tool to register
    public func register(_ tool: Tool) {
        tools[tool.name] = tool
    }
    
    /// Registers multiple tools
    /// - Parameter tools: The tools to register
    public func register(_ tools: [Tool]) {
        for tool in tools {
            register(tool)
        }
    }
    
    /// Removes a tool by name
    /// - Parameter name: The name of the tool to remove
    public func unregister(name: String) {
        tools.removeValue(forKey: name)
    }
    
    /// Returns a tool by name
    /// - Parameter name: The name of the tool
    /// - Returns: The tool if found, nil otherwise
    public func getTool(named name: String) -> Tool? {
        return tools[name]
    }
    
    /// Returns all registered tool names
    public var registeredToolNames: [String] {
        return Array(tools.keys)
    }
    
    /// Sets a custom handler for tool calls
    /// - Parameter handler: The custom handler closure
    public func setCustomHandler(_ handler: (@Sendable (ToolCall) async throws -> String)?) {
        self.customHandler = handler
    }
    
    // MARK: - Tool Execution
    
    /// Executes a tool call
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool result
    public func execute(toolCall: ToolCall) async -> ToolResult {
        // Check if there's a custom handler
        if let handler = customHandler {
            do {
                let output = try await handler(toolCall)
                return ToolResult(toolCallId: toolCall.id, output: output)
            } catch {
                return ToolResult(toolCallId: toolCall.id, error: error.localizedDescription)
            }
        }
        
        // Look up the tool by name
        guard let tool = tools[toolCall.name] else {
            print("[ToolExecutor] ⚠️ Tool '\(toolCall.name)' not found in registered tools")
            return ToolResult(toolCallId: toolCall.id, error: "Tool '\(toolCall.name)' not registered")
        }
        
        // Execute the tool
        print("[ToolExecutor] 🔧 Executing tool: \(toolCall.name)")
        let result = await tool.execute(with: toolCall.arguments, callId: toolCall.id)
        
        if result.isSuccess {
            print("[ToolExecutor] ✅ Tool '\(toolCall.name)' executed successfully")
        } else {
            print("[ToolExecutor] ❌ Tool '\(toolCall.name)' failed: \(result.error ?? "unknown error")")
        }
        
        return result
    }
}

