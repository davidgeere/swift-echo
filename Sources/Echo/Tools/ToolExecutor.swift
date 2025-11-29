// ToolExecutor.swift
// Echo - Tool Execution
// Centralized tool execution with direct method calls (no event-based coordination)

import Foundation

/// Centralized tool executor that handles automatic and custom tool execution.
/// Called directly by RealtimeClient/Conversation instead of through events.
public actor ToolExecutor: ToolExecuting {
    // MARK: - Properties
    
    /// Registered tools by name
    private var tools: [String: Tool] = [:]
    
    /// Optional custom handler provider for manual tool handling
    private weak var customHandlerProvider: (any ToolHandlerProvider)?
    
    /// Event emitter for external notifications (observation only)
    private let eventEmitter: EventEmitter
    
    // MARK: - Initialization
    
    /// Creates a new ToolExecutor
    /// - Parameters:
    ///   - eventEmitter: Event emitter for external notifications
    ///   - customHandlerProvider: Optional provider of custom tool handlers
    public init(
        eventEmitter: EventEmitter,
        customHandlerProvider: (any ToolHandlerProvider)? = nil
    ) {
        self.eventEmitter = eventEmitter
        self.customHandlerProvider = customHandlerProvider
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
            self.tools[tool.name] = tool
        }
    }
    
    /// Unregisters a tool by name
    /// - Parameter name: The name of the tool to unregister
    public func unregister(named name: String) {
        tools.removeValue(forKey: name)
    }
    
    /// Returns a registered tool by name
    /// - Parameter name: The tool name
    /// - Returns: The tool if registered, nil otherwise
    public func getTool(named name: String) -> Tool? {
        return tools[name]
    }
    
    /// Returns all registered tool names
    public var registeredToolNames: [String] {
        return Array(tools.keys)
    }
    
    // MARK: - Tool Execution (ToolExecuting Protocol)
    
    /// Executes a tool call and returns the result.
    /// If a custom handler is set, it takes precedence over automatic execution.
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool result
    public func execute(toolCall: ToolCall) async -> ToolResult {
        // Emit event for external observation
        await eventEmitter.emit(.toolCallRequested(toolCall: toolCall))
        
        // Check for custom handler first
        if let customHandler = customHandlerProvider?.toolHandler {
            do {
                print("[ToolExecutor] 🔧 Executing tool '\(toolCall.name)' via custom handler")
                let output = try await customHandler(toolCall)
                
                let result = ToolResult(toolCallId: toolCall.id, output: output)
                
                // Emit result for external observation
                await eventEmitter.emit(.toolResultSubmitted(
                    toolCallId: result.toolCallId,
                    result: result.output
                ))
                
                return result
            } catch {
                print("[ToolExecutor] ❌ Custom handler failed for '\(toolCall.name)': \(error)")
                
                let result = ToolResult(toolCallId: toolCall.id, error: error.localizedDescription)
                
                await eventEmitter.emit(.toolResultSubmitted(
                    toolCallId: result.toolCallId,
                    result: "{\"error\": \"\(error.localizedDescription)\"}"
                ))
                
                return result
            }
        }
        
        // Automatic execution using registered tools
        guard let tool = tools[toolCall.name] else {
            print("[ToolExecutor] ⚠️ Tool '\(toolCall.name)' not found in registered tools")
            
            let result = ToolResult(toolCallId: toolCall.id, error: "Tool '\(toolCall.name)' not registered")
            
            await eventEmitter.emit(.toolResultSubmitted(
                toolCallId: result.toolCallId,
                result: "{\"error\": \"Tool '\(toolCall.name)' not registered\"}"
            ))
            
            return result
        }
        
        // Execute the registered tool
        print("[ToolExecutor] 🔧 Executing tool: \(toolCall.name)")
        let result = await tool.execute(with: toolCall.arguments, callId: toolCall.id)
        
        // Emit result for external observation
        if result.isSuccess {
            print("[ToolExecutor] ✅ Tool '\(toolCall.name)' executed successfully")
        } else {
            print("[ToolExecutor] ❌ Tool '\(toolCall.name)' failed: \(result.error ?? "unknown error")")
        }
        
        await eventEmitter.emit(.toolResultSubmitted(
            toolCallId: result.toolCallId,
            result: result.output
        ))
        
        return result
    }
    
    // MARK: - Custom Handler
    
    /// Sets the custom handler provider
    /// - Parameter provider: The provider of custom tool handlers
    public func setCustomHandlerProvider(_ provider: (any ToolHandlerProvider)?) {
        self.customHandlerProvider = provider
    }
}

