// Echo.swift
// Echo - Main Entry Point
// The public API for the Echo library

import Foundation
import Observation

/// Main entry point for the Echo library providing unified access to
/// OpenAI's Realtime and Responses APIs with seamless mode switching.
@Observable
public class Echo {
    // MARK: - Configuration

    /// The configuration for this Echo instance
    public let configuration: EchoConfiguration

    /// API key for OpenAI
    internal let apiKey: String

    /// Event emitter for the echo.when() syntax
    internal let eventEmitter: EventEmitter

    /// Registered tools for function calling
    private var tools: [Tool] = []

    /// Registered MCP servers
    private var mcpServers: [MCPServer] = []

    /// Tool registry actor for thread-safe access from Sendable closures
    private let toolRegistry = ToolRegistry()

    // MARK: - Initialization

    /// Creates a new Echo instance
    /// - Parameters:
    ///   - key: OpenAI API key
    ///   - configuration: Optional configuration (uses defaults if not provided)
    ///   - automaticToolExecution: If true, registered tools execute automatically (default: true)
    public init(
        key: String,
        configuration: EchoConfiguration = EchoConfiguration(),
        automaticToolExecution: Bool = true
    ) {
        self.apiKey = key
        self.configuration = configuration
        self.eventEmitter = EventEmitter()

        // Log version info on initialization
        if configuration.logLevel != .none {
            print("🔊 \(EchoVersion.full) initialized")
        }
        
        // Set up automatic tool execution if enabled
        if automaticToolExecution {
            setupAutomaticToolExecution()
        }
    }

    /// Sets up automatic tool execution for registered tools
    private func setupAutomaticToolExecution() {
        let emitter = eventEmitter
        let registry = toolRegistry

        Task {
            await emitter.when(.toolCallRequested) { event in
                guard case .toolCallRequested(let toolCall) = event else { return }

                // Look up the tool by name from registry
                guard let tool = await registry.getTool(named: toolCall.name) else {
                    // Tool not registered - submit error
                    print("[Echo] ⚠️  Tool '\(toolCall.name)' not found in registered tools")
                    await emitter.emit(.toolResultSubmitted(
                        toolCallId: toolCall.id,
                        result: "{\"error\": \"Tool '\(toolCall.name)' not registered\"}"
                    ))
                    return
                }

                // Execute the tool
                print("[Echo] 🔧 Executing tool: \(toolCall.name)")
                let result = await tool.execute(with: toolCall.arguments, callId: toolCall.id)

                // Submit the result
                if result.isSuccess {
                    print("[Echo] ✅ Tool '\(toolCall.name)' executed successfully")
                    await emitter.emit(.toolResultSubmitted(
                        toolCallId: result.toolCallId,
                        result: result.output
                    ))
                } else {
                    print("[Echo] ❌ Tool '\(toolCall.name)' failed: \(result.error ?? "unknown error")")
                    await emitter.emit(.toolResultSubmitted(
                        toolCallId: result.toolCallId,
                        result: "{\"error\": \"\(result.error ?? "unknown error")\"}"
                    ))
                }
            }
        }
    }

    // MARK: - Conversation Management

    /// Starts a new conversation
    /// - Parameters:
    ///   - mode: The initial mode (audio or text)
    ///   - systemMessage: Optional system instructions for the model
    /// - Returns: A Conversation instance for managing the conversation
    /// - Throws: EchoError if conversation cannot be started
    public func startConversation(
        mode: EchoMode,
        systemMessage: String? = nil
    ) async throws -> Conversation {
        return try await Conversation(
            apiKey: apiKey,
            mode: mode,
            configuration: configuration,
            systemMessage: systemMessage,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers
        )
    }

    /// Starts a new conversation with specific turn mode
    /// - Parameters:
    ///   - mode: The initial mode (audio or text)
    ///   - turnMode: Turn detection mode (overrides configuration default)
    ///   - systemMessage: Optional system instructions for the model
    /// - Returns: A Conversation instance for managing the conversation
    /// - Throws: EchoError if conversation cannot be started
    public func startConversation(
        mode: EchoMode,
        turnMode: TurnDetection,
        systemMessage: String? = nil
    ) async throws -> Conversation {
        // Create a custom configuration with the specified turn mode
        // EchoConfiguration has let properties, so we create a new instance with overrides
        let configWithTurnMode = EchoConfiguration(
            defaultMode: configuration.defaultMode,
            realtimeModel: configuration.realtimeModel,
            responsesModel: configuration.responsesModel,
            audioFormat: configuration.audioFormat,
            voice: configuration.voice,
            turnDetection: turnMode,  // Override with specified turn mode
            temperature: configuration.temperature,
            maxTokens: configuration.maxTokens,
            enableTranscription: configuration.enableTranscription,
            logLevel: configuration.logLevel
        )

        return try await Conversation(
            apiKey: apiKey,
            mode: mode,
            configuration: configWithTurnMode,
            systemMessage: systemMessage,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers
        )
    }

    // MARK: - Event Registration

    /// Registers a synchronous event handler
    /// - Parameters:
    ///   - eventType: The type of event to listen for
    ///   - handler: The handler closure to call when the event occurs
    public func when(
        _ eventType: EventType,
        handler: @escaping @Sendable (EchoEvent) -> Void
    ) {
        let emitter = eventEmitter
        Task {
            await emitter.when(eventType, handler: handler)
        }
    }

    /// Registers an asynchronous event handler
    /// - Parameters:
    ///   - eventType: The type of event to listen for
    ///   - asyncHandler: The async handler closure to call when the event occurs
    public func when(
        _ eventType: EventType,
        asyncHandler: @escaping @Sendable (EchoEvent) async -> Void
    ) {
        let emitter = eventEmitter
        Task {
            await emitter.when(eventType, asyncHandler: asyncHandler)
        }
    }

    // MARK: - Tool Registration

    /// Registers a tool/function that can be called by the model
    /// - Parameter tool: The tool to register
    public func registerTool(_ tool: Tool) {
        tools.append(tool)
        // Also register in the actor for Sendable access
        let registry = toolRegistry
        Task {
            await registry.register(tool)
        }
    }

    /// Registers a manual handler for tool calls (overrides automatic execution)
    /// Use this to intercept tool calls for approval, custom logic, etc.
    /// - Parameter handler: The handler closure that receives the tool call and returns output string
    /// - Note: When this is used, automatic tool execution is bypassed for intercepted calls
    public func when(
        call handler: @escaping @Sendable (ToolCall) async throws -> String
    ) {
        let emitter = eventEmitter
        Task {
            await emitter.when(.toolCallRequested) { event in
                guard case .toolCallRequested(let toolCall) = event else { return }
                do {
                    let output = try await handler(toolCall)
                    // Emit tool result with correct call_id
                    await emitter.emit(.toolResultSubmitted(
                        toolCallId: toolCall.id,  // ✅ Use actual call ID
                        result: output
                    ))
                } catch {
                    // Submit error with correct call_id
                    await emitter.emit(.toolResultSubmitted(
                        toolCallId: toolCall.id,  // ✅ Use actual call ID
                        result: "{\"error\": \"\(error.localizedDescription)\"}"
                    ))
                }
            }
        }
    }

    /// Manually submit a tool result (for advanced use cases)
    /// - Parameters:
    ///   - callId: The tool call ID from the `.toolCallRequested` event
    ///   - output: The result output as a JSON string
    public func submitToolResult(callId: String, output: String) async {
        await eventEmitter.emit(.toolResultSubmitted(toolCallId: callId, result: output))
    }

    /// Manually submit a tool error (for advanced use cases)
    /// - Parameters:
    ///   - callId: The tool call ID from the `.toolCallRequested` event
    ///   - error: The error message
    public func submitToolError(callId: String, error: String) async {
        await eventEmitter.emit(.toolResultSubmitted(toolCallId: callId, result: "{\"error\": \"\(error)\"}"))
    }

    /// Returns all registered tools
    internal func getTools() -> [Tool] {
        return tools
    }

    // MARK: - MCP Server Registration

    /// Registers an MCP (Model Context Protocol) server
    /// - Parameter server: The MCP server to register
    public func registerMCPServer(_ server: MCPServer) {
        mcpServers.append(server)
    }

    /// Returns all registered MCP servers
    internal func getMCPServers() -> [MCPServer] {
        return mcpServers
    }
}

// MARK: - Tool Registry Actor

/// Actor for thread-safe tool registry access from Sendable closures
actor ToolRegistry {
    private var tools: [Tool] = []

    func register(_ tool: Tool) {
        tools.append(tool)
    }

    func getTool(named name: String) -> Tool? {
        return tools.first(where: { $0.name == name })
    }
}

// MARK: - Embeddings Extension (Legacy API)

extension Echo {
    // MARK: - Embeddings API (Backwards Compatibility)
    
    /// Generates an embedding for a single text
    /// - Parameters:
    ///   - text: The text to embed
    ///   - model: The embedding model to use (default: text-embedding-3-small)
    ///   - dimensions: Optional custom dimensions (for models that support it)
    /// - Returns: The embedding vector as an array of Float values
    /// - Throws: EchoError if the request fails
    /// - Note: Consider using `echo.generate.embedding(from:)` for better discoverability
    @available(*, deprecated, message: "Use echo.generate.embedding(from:) instead")
    public func generateEmbedding(
        text: String,
        model: EmbeddingModel = .textEmbedding3Small,
        dimensions: Int? = nil
    ) async throws -> [Float] {
        return try await generate.embedding(from: text, model: model, dimensions: dimensions)
    }
    
    /// Generates embeddings for multiple texts
    /// - Parameters:
    ///   - texts: Array of texts to embed
    ///   - model: The embedding model to use (default: text-embedding-3-small)
    ///   - dimensions: Optional custom dimensions (for models that support it)
    /// - Returns: Array of embedding vectors in the same order as input
    /// - Throws: EchoError if the request fails
    /// - Note: Consider using `echo.generate.embeddings(from:)` for better discoverability
    @available(*, deprecated, message: "Use echo.generate.embeddings(from:) instead")
    public func generateEmbeddings(
        texts: [String],
        model: EmbeddingModel = .textEmbedding3Small,
        dimensions: Int? = nil
    ) async throws -> [[Float]] {
        return try await generate.embeddings(from: texts, model: model, dimensions: dimensions)
    }
    
    /// Finds the most similar texts from a corpus
    /// - Parameters:
    ///   - query: The query text
    ///   - corpus: Array of texts to search through
    ///   - topK: Number of results to return (default: 10)
    ///   - model: The embedding model to use (default: text-embedding-3-small)
    /// - Returns: Array of (index, text, similarity) tuples, sorted by similarity
    /// - Throws: EchoError if embedding generation fails
    /// - Note: Consider using `echo.find.similar(to:in:)` for better discoverability
    @available(*, deprecated, message: "Use echo.find.similar(to:in:) instead")
    public func findSimilarTexts(
        query: String,
        in corpus: [String],
        topK: Int = 10,
        model: EmbeddingModel = .textEmbedding3Small
    ) async throws -> [(index: Int, text: String, similarity: Float)] {
        return try await find.similar(to: query, in: corpus, topK: topK, model: model)
    }
}

// MARK: - Structured Outputs Extension (Legacy API)

extension Echo {
    // MARK: - Structured Outputs (Backwards Compatibility)

    /// Generates a structured output using JSON schema
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - schema: The Codable type to generate
    ///   - model: The Responses model to use (defaults to configuration default)
    ///   - instructions: Optional system instructions
    /// - Returns: Decoded instance of the specified type
    /// - Throws: EchoError if generation or decoding fails
    /// - Note: Consider using `echo.generate.structured(_:from:)` for better discoverability
    @available(*, deprecated, message: "Use echo.generate.structured(_:from:) instead")
    public func generateStructured<T: Codable & Sendable>(
        prompt: String,
        schema: T.Type,
        model: ResponsesModel? = nil,
        instructions: String? = nil
    ) async throws -> T {
        return try await generate.structured(schema, from: prompt, model: model, instructions: instructions)
    }

    /// Generates structured JSON output using a custom schema
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - jsonSchema: Custom JSON schema definition
    ///   - model: The Responses model to use (defaults to configuration default)
    ///   - instructions: Optional system instructions
    /// - Returns: Raw JSON string
    /// - Throws: EchoError if generation fails
    /// - Note: Consider using `echo.generate.structuredJSON(schema:from:)` for better discoverability
    @available(*, deprecated, message: "Use echo.generate.structuredJSON(schema:from:) instead")
    public func generateStructuredJSON(
        prompt: String,
        jsonSchema: JSONSchema,
        model: ResponsesModel? = nil,
        instructions: String? = nil
    ) async throws -> String {
        return try await generate.structuredJSON(schema: jsonSchema, from: prompt, model: model, instructions: instructions)
    }

    // MARK: - Internal Testing Support

    /// Internal method for creating conversations with mock audio components (testing only)
    /// - Parameters:
    ///   - mode: The initial mode (audio or text)
    ///   - systemMessage: Optional system instructions for the model
    ///   - audioCaptureFactory: Factory for creating audio capture
    ///   - audioPlaybackFactory: Factory for creating audio playback
    /// - Returns: A Conversation instance for managing the conversation
    /// - Throws: EchoError if conversation cannot be started
    internal func startConversation(
        mode: EchoMode,
        systemMessage: String? = nil,
        audioCaptureFactory: (@Sendable () async -> any AudioCaptureProtocol)?,
        audioPlaybackFactory: (@Sendable () async -> any AudioPlaybackProtocol)?
    ) async throws -> Conversation {
        return try await Conversation(
            apiKey: apiKey,
            mode: mode,
            configuration: configuration,
            systemMessage: systemMessage,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers,
            audioCaptureFactory: audioCaptureFactory,
            audioPlaybackFactory: audioPlaybackFactory
        )
    }
}
