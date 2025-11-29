// ToolExecutor.swift
// Echo - Tool Execution
// Centralized tool execution actor called directly by RealtimeClient

import Foundation

/// Centralized tool executor that handles tool calls directly
/// This replaces event-based tool execution to avoid orphaned Tasks
public actor ToolExecutor: ToolExecuting {
    // MARK: - Properties
    
    /// Registered tools by name
    private var tools: [String: Tool] = [:]
    
    /// Optional custom handler closure
    private var customHandler: (@Sendable (ToolCall) async throws -> String)?
    
    /// Event emitter for notifications (fire-and-forget)
    private let eventEmitter: EventEmitter?
    
    // MARK: - Initialization
    
    /// Creates a new ToolExecutor
    /// - Parameters:
    ///   - eventEmitter: Optional event emitter for notifications
    public init(eventEmitter: EventEmitter? = nil) {
        self.eventEmitter = eventEmitter
        self.customHandler = nil
    }
    
    /// Sets a custom handler for tool calls
    /// - Parameter handler: The custom handler closure
    public func setCustomHandler(_ handler: @escaping @Sendable (ToolCall) async throws -> String) {
        self.customHandler = handler
    }
    
    /// Clears the custom handler
    public func clearCustomHandler() {
        self.customHandler = nil
    }
    
    // MARK: - Tool Registration
    
    /// Registers a tool for execution
    /// - Parameter tool: The tool to register
    public func register(_ tool: Tool) {
        tools[tool.name] = tool
    }
    
    /// Registers multiple tools
    /// - Parameter tools: The tools to register
    public func register(_ tools: [Tool]) {
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }
    
    /// Unregisters a tool by name
    /// - Parameter name: The name of the tool to unregister
    public func unregister(named name: String) {
        tools.removeValue(forKey: name)
    }
    
    /// Checks if a tool is registered
    /// - Parameter name: The tool name to check
    /// - Returns: True if the tool is registered
    public func isRegistered(named name: String) -> Bool {
        return tools[name] != nil
    }
    
    /// Gets a registered tool by name
    /// - Parameter name: The tool name
    /// - Returns: The tool if registered, nil otherwise
    public func getTool(named name: String) -> Tool? {
        return tools[name]
    }
    
    // MARK: - Tool Execution
    
    /// Executes a tool call and returns the result
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool result
    public func execute(toolCall: ToolCall) async -> ToolResult {
        // Check for custom handler first
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
            return ToolResult(toolCallId: toolCall.id, error: "Tool '\(toolCall.name)' not registered")
        }
        
        // Execute the tool
        let result = await tool.execute(with: toolCall.arguments, callId: toolCall.id)
        
        // Emit notification event (fire-and-forget)
        if let emitter = eventEmitter {
            if result.isSuccess {
                await emitter.emit(.toolExecutionCompleted(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    output: result.output
                ))
            } else {
                await emitter.emit(.toolExecutionFailed(
                    toolCallId: toolCall.id,
                    toolName: toolCall.name,
                    error: result.error ?? "Unknown error"
                ))
            }
        }
        
        return result
    }
    
    // MARK: - Diagnostics
    
    /// Returns all registered tool names
    public var registeredToolNames: [String] {
        return Array(tools.keys)
    }
    
    /// Returns the count of registered tools
    public var registeredToolCount: Int {
        return tools.count
    }
}

