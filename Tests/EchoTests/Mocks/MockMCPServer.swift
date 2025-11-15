// MockMCPServer.swift
// Echo Tests - Mock Infrastructure
// Mock MCP server for testing without real server connections

import Foundation
@testable import Echo

/// Mock MCP server for testing
public actor MockMCPServer {
    private var registeredTools: [String: MockTool] = [:]
    private var executionHistory: [ToolExecution] = []
    private var shouldFailDiscovery = false
    private var shouldFailExecution = false
    private var discoveryDelay: TimeInterval = 0
    private var executionDelay: TimeInterval = 0
    private var approvalResponses: [String: Bool] = [:]
    
    /// Represents a mock tool
    public struct MockTool: Sendable {
        public let name: String
        public let description: String
        public let parameters: [String: String]  // Simplified parameter schema
        public let handler: @Sendable ([String: String]) async throws -> String
        
        public init(
            name: String,
            description: String,
            parameters: [String: String] = [:],
            handler: @escaping @Sendable ([String: String]) async throws -> String = { _ in "Mock result" }
        ) {
            self.name = name
            self.description = description
            self.parameters = parameters
            self.handler = handler
        }
    }
    
    /// Record of a tool execution
    public struct ToolExecution: Sendable {
        public let toolName: String
        public let arguments: [String: String]
        public let result: Result<String, any Error>
        public let timestamp: Date
        public let approved: Bool
    }
    
    // MARK: - Configuration
    
    /// Configure the mock server to fail discovery
    public func setDiscoveryFailure(_ shouldFail: Bool, delay: TimeInterval = 0) {
        self.shouldFailDiscovery = shouldFail
        self.discoveryDelay = delay
    }
    
    /// Configure the mock server to fail execution
    public func setExecutionFailure(_ shouldFail: Bool, delay: TimeInterval = 0) {
        self.shouldFailExecution = shouldFail
        self.executionDelay = delay
    }
    
    /// Set approval response for a specific tool
    public func setApprovalResponse(for toolName: String, approved: Bool) {
        approvalResponses[toolName] = approved
    }
    
    // MARK: - Tool Management
    
    /// Register a mock tool
    public func registerTool(_ tool: MockTool) {
        registeredTools[tool.name] = tool
    }
    
    /// Register multiple mock tools
    public func registerTools(_ tools: [MockTool]) {
        for tool in tools {
            registeredTools[tool.name] = tool
        }
    }
    
    /// Clear all registered tools
    public func clearTools() {
        registeredTools.removeAll()
    }
    
    // MARK: - Tool Discovery
    
    /// Simulate tool discovery
    public func discoverTools() async throws -> [Tool] {
        // Simulate network delay
        if discoveryDelay > 0 {
            try await Task.sleep(for: .seconds(discoveryDelay))
        }
        
        // Simulate discovery failure
        if shouldFailDiscovery {
            throw MCPError.discoveryFailed("Mock discovery failure")
        }
        
        // Convert mock tools to Echo Tools
        return registeredTools.values.map { mockTool in
            Tool(
                name: mockTool.name,
                description: mockTool.description,
                parameters: ToolParameters(
                    properties: mockTool.parameters.mapValues { desc in
                        ParameterSchema.string(description: desc)
                    },
                    required: Array(mockTool.parameters.keys)
                ),
                handler: { [weak self] args in
                    guard let self = self else { return "Server disconnected" }
                    
                    // Convert AnyCodable to string dictionary
                    var plainArgs: [String: String] = [:]
                    for (key, value) in args {
                        plainArgs[key] = String(describing: value.value)
                    }
                    
                    return try await self.executeTool(
                        name: mockTool.name,
                        arguments: plainArgs,
                        handler: mockTool.handler
                    )
                }
            )
        }
    }
    
    // MARK: - Tool Execution
    
    /// Execute a tool with approval check
    private func executeTool(
        name: String,
        arguments: [String: String],
        handler: ([String: String]) async throws -> String
    ) async throws -> String {
        // Simulate execution delay
        if executionDelay > 0 {
            try await Task.sleep(for: .seconds(executionDelay))
        }
        
        // Check approval
        let approved = approvalResponses[name] ?? true
        
        // Simulate execution failure
        if shouldFailExecution {
            let error = MCPError.executionFailed("Mock execution failure for \(name)")
            let execution = ToolExecution(
                toolName: name,
                arguments: arguments,
                result: .failure(error),
                timestamp: Date(),
                approved: approved
            )
            executionHistory.append(execution)
            throw error
        }
        
        // Execute the handler
        do {
            let result = try await handler(arguments)
            let execution = ToolExecution(
                toolName: name,
                arguments: arguments,
                result: .success(result),
                timestamp: Date(),
                approved: approved
            )
            executionHistory.append(execution)
            return result
        } catch {
            let execution = ToolExecution(
                toolName: name,
                arguments: arguments,
                result: .failure(error),
                timestamp: Date(),
                approved: approved
            )
            executionHistory.append(execution)
            throw error
        }
    }
    
    // MARK: - History and Verification
    
    /// Get execution history
    public func getExecutionHistory() -> [ToolExecution] {
        return executionHistory
    }
    
    /// Clear execution history
    public func clearHistory() {
        executionHistory.removeAll()
    }
    
    /// Check if a tool was executed
    public func wasToolExecuted(_ toolName: String) -> Bool {
        return executionHistory.contains { $0.toolName == toolName }
    }
    
    /// Get executions for a specific tool
    public func getExecutions(for toolName: String) -> [ToolExecution] {
        return executionHistory.filter { $0.toolName == toolName }
    }
    
    /// Get the last execution result
    public func getLastExecutionResult() -> Result<String, Error>? {
        return executionHistory.last?.result
    }
    
    // MARK: - Preset Configurations
    
    /// Configure as a weather service
    public func configureAsWeatherService() {
        clearTools()
        
        registerTool(MockTool(
            name: "get_current_weather",
            description: "Get current weather for a location",
            parameters: ["location": "City name or coordinates"],
            handler: { args in
                let location = args["location"] ?? "Unknown"
                return "Weather in \(location): Sunny, 72°F"
            }
        ))
        
        registerTool(MockTool(
            name: "get_forecast",
            description: "Get weather forecast",
            parameters: [
                "location": "City name or coordinates",
                "days": "Number of days (1-7)"
            ],
            handler: { args in
                let location = args["location"] ?? "Unknown"
                let days = Int(args["days"] ?? "3") ?? 3
                return "Forecast for \(location): Sunny for next \(days) days"
            }
        ))
    }
    
    /// Configure as a database service
    public func configureAsDatabaseService() {
        clearTools()
        
        registerTool(MockTool(
            name: "query_database",
            description: "Execute database query",
            parameters: [
                "query": "SQL query string",
                "database": "Database name"
            ],
            handler: { args in
                let query = args["query"] ?? ""
                if query.lowercased().contains("select") {
                    return "Results: [{id: 1, name: 'Test'}]"
                } else if query.lowercased().contains("insert") {
                    return "1 row inserted"
                } else if query.lowercased().contains("update") {
                    return "2 rows updated"
                } else {
                    return "Query executed successfully"
                }
            }
        ))
        
        registerTool(MockTool(
            name: "list_tables",
            description: "List all tables in database",
            parameters: ["database": "Database name"],
            handler: { args in
                return "Tables: users, products, orders"
            }
        ))
    }
    
    /// Configure with error-prone tools
    public func configureWithFaultyTools() {
        clearTools()
        
        registerTool(MockTool(
            name: "unreliable_tool",
            description: "Sometimes fails",
            parameters: ["input": "Any input"],
            handler: { args in
                // Randomly fail 50% of the time
                if Int.random(in: 0...1) == 0 {
                    throw MCPError.executionFailed("Random failure occurred")
                }
                return "Success this time!"
            }
        ))
        
        registerTool(MockTool(
            name: "slow_tool",
            description: "Takes a long time",
            parameters: ["timeout": "Timeout in seconds"],
            handler: { args in
                let timeout = Double(args["timeout"] ?? "5.0") ?? 5.0
                try await Task.sleep(for: .seconds(timeout))
                return "Completed after \(timeout) seconds"
            }
        ))
        
        registerTool(MockTool(
            name: "always_fails",
            description: "Always throws an error",
            parameters: [:],
            handler: { _ in
                throw MCPError.executionFailed("This tool is designed to fail")
            }
        ))
    }
}

// MARK: - MCP Errors

public enum MCPError: Error, LocalizedError {
    case discoveryFailed(String)
    case executionFailed(String)
    case approvalDenied(String)
    case timeout(String)
    case invalidArguments(String)
    
    public var errorDescription: String? {
        switch self {
        case .discoveryFailed(let message):
            return "Tool discovery failed: \(message)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        case .approvalDenied(let tool):
            return "Approval denied for tool: \(tool)"
        case .timeout(let message):
            return "Operation timed out: \(message)"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        }
    }
}

// MARK: - Test Helper Extensions

extension MockMCPServer {
    /// Verify a sequence of tool executions
    public func verifyExecutionSequence(_ expectedTools: [String]) -> Bool {
        let executedTools = executionHistory.map { $0.toolName }
        return executedTools == expectedTools
    }
    
    /// Get successful executions only
    public func getSuccessfulExecutions() -> [ToolExecution] {
        return executionHistory.filter {
            if case .success = $0.result {
                return true
            }
            return false
        }
    }
    
    /// Get failed executions only
    public func getFailedExecutions() -> [ToolExecution] {
        return executionHistory.filter {
            if case .failure = $0.result {
                return true
            }
            return false
        }
    }
    
    /// Reset all configurations
    public func reset() {
        clearTools()
        clearHistory()
        shouldFailDiscovery = false
        shouldFailExecution = false
        discoveryDelay = 0
        executionDelay = 0
        approvalResponses.removeAll()
    }
}

// Note: TestBundleMarker is defined in VCR.swift
