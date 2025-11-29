// ToolExecutor.swift
// Echo - Tools
// Centralized tool execution actor for thread-safe tool handling

import Foundation

/// Centralized tool executor that manages tool registration and execution
/// Called directly by RealtimeClient instead of through events
public actor ToolExecutor: ToolExecuting {
    // MARK: - Properties
    
    /// Registered tools by name
    private var tools: [String: Tool] = [:]
    
    /// Optional custom handler provider for intercepting tool calls
    private weak var customHandlerProvider: (any ToolHandlerProvider)?
    
    /// Event emitter for notifications (fire-and-forget only)
    private let eventEmitter: EventEmitter
    
    // MARK: - Initialization
    
    /// Creates a new ToolExecutor
    /// - Parameters:
    ///   - eventEmitter: Event emitter for notifications
    ///   - customHandlerProvider: Optional provider for custom tool handling
    public init(
        eventEmitter: EventEmitter,
        customHandlerProvider: (any ToolHandlerProvider)? = nil
    ) {
        self.eventEmitter = eventEmitter
        self.customHandlerProvider = customHandlerProvider
    }
    
    // MARK: - Tool Registration
    
    /// Registers a tool for execution
    /// - Parameter tool: The tool to register
    public func register(_ tool: Tool) {
        tools[tool.name] = tool
    }
    
    /// Registers multiple tools
    /// - Parameter tools: Array of tools to register
    public func registerAll(_ tools: [Tool]) {
        for tool in tools {
            register(tool)
        }
    }
    
    /// Unregisters a tool by name
    /// - Parameter name: The name of the tool to unregister
    /// - Returns: True if the tool was found and removed
    @discardableResult
    public func unregister(named name: String) -> Bool {
        return tools.removeValue(forKey: name) != nil
    }
    
    /// Gets a registered tool by name
    /// - Parameter name: The tool name
    /// - Returns: The tool if registered, nil otherwise
    public func getTool(named name: String) -> Tool? {
        return tools[name]
    }
    
    /// Returns all registered tool names
    public var registeredToolNames: [String] {
        return Array(tools.keys)
    }
    
    // MARK: - Tool Execution
    
    /// Executes a tool call and returns the result
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool execution result
    public func execute(toolCall: ToolCall) async -> ToolResult {
        // Emit event that tool call was requested (observation only)
        await eventEmitter.emit(.toolCallRequested(toolCall: toolCall))
        
        // Check for custom handler first
        if let provider = customHandlerProvider,
           let customHandler = provider.toolHandler {
            do {
                let output = try await customHandler(toolCall)
                let result = ToolResult(toolCallId: toolCall.id, output: output)
                
                // Emit result notification
                await eventEmitter.emit(.toolResultSubmitted(
                    toolCallId: toolCall.id,
                    result: output
                ))
                
                return result
            } catch {
                let errorResult = ToolResult(toolCallId: toolCall.id, error: error.localizedDescription)
                
                await eventEmitter.emit(.toolResultSubmitted(
                    toolCallId: toolCall.id,
                    result: "{\"error\": \"\(error.localizedDescription)\"}"
                ))
                
                return errorResult
            }
        }
        
        // Look up registered tool
        guard let tool = tools[toolCall.name] else {
            let errorMessage = "Tool '\(toolCall.name)' not registered"
            let errorResult = ToolResult(toolCallId: toolCall.id, error: errorMessage)
            
            await eventEmitter.emit(.toolResultSubmitted(
                toolCallId: toolCall.id,
                result: errorResult.output
            ))
            
            return errorResult
        }
        
        // Execute the tool
        let result = await tool.execute(with: toolCall.arguments, callId: toolCall.id)
        
        // Emit result notification
        await eventEmitter.emit(.toolResultSubmitted(
            toolCallId: result.toolCallId,
            result: result.output
        ))
        
        return result
    }
    
    // MARK: - Configuration
    
    /// Sets the custom handler provider
    /// - Parameter provider: The provider for custom tool handling
    public func setCustomHandlerProvider(_ provider: (any ToolHandlerProvider)?) {
        self.customHandlerProvider = provider
    }
}

