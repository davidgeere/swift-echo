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

    /// Event emitter for the events stream
    internal let eventEmitter: EventEmitter

    /// Registered tools for function calling
    private var tools: [Tool] = []

    /// Registered MCP servers
    private var mcpServers: [MCPServer] = []

    /// Tool executor for centralized tool execution
    internal let toolExecutor: ToolExecutor
    
    /// Optional custom tool handler. If nil, tools execute automatically.
    /// If set, this is called instead of automatic execution.
    ///
    /// ## Usage
    /// ```swift
    /// echo.toolHandler = { toolCall in
    ///     // Custom logic before execution
    ///     if await userApproves(toolCall) {
    ///         return await executeTool(toolCall)
    ///     } else {
    ///         throw ToolError.userDenied
    ///     }
    /// }
    /// ```
    private var _toolHandler: (@Sendable (ToolCall) async throws -> String)?
    
    /// Sets a custom tool handler
    /// - Parameter handler: The handler to use for tool calls
    public func setToolHandler(_ handler: (@Sendable (ToolCall) async throws -> String)?) async {
        _toolHandler = handler
        await toolExecutor.setCustomHandler(handler)
    }
    
    /// Gets the current tool handler
    public var toolHandler: (@Sendable (ToolCall) async throws -> String)? {
        return _toolHandler
    }

    // MARK: - Initialization

    /// Creates a new Echo instance
    /// - Parameters:
    ///   - key: OpenAI API key
    ///   - configuration: Optional configuration (uses defaults if not provided)
    public init(
        key: String,
        configuration: EchoConfiguration = EchoConfiguration()
    ) {
        self.apiKey = key
        self.configuration = configuration
        self.eventEmitter = EventEmitter()
        self.toolExecutor = ToolExecutor()

        // Log version info on initialization
        if configuration.logLevel != .none {
            print("🔊 \(EchoVersion.full) initialized")
        }
    }

    // MARK: - Conversation Management

    /// Starts a new conversation
    /// - Parameters:
    ///   - mode: The initial mode (audio or text)
    ///   - systemMessage: Optional system instructions for the model (overrides config default if provided)
    /// - Returns: A Conversation instance for managing the conversation
    /// - Throws: EchoError if conversation cannot be started
    public func startConversation(
        mode: EchoMode,
        systemMessage: String? = nil
    ) async throws -> Conversation {
        // Use provided systemMessage or fall back to config's default
        let finalSystemMessage = systemMessage ?? configuration.systemMessage
        
        return try await Conversation(
            apiKey: apiKey,
            mode: mode,
            configuration: configuration,
            systemMessage: finalSystemMessage,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers,
            toolExecutor: toolExecutor
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
        // Use provided systemMessage or fall back to config's default
        let finalSystemMessage = systemMessage ?? configuration.systemMessage
        
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
            reasoningEffort: configuration.reasoningEffort,
            systemMessage: configuration.systemMessage,  // Preserve config's systemMessage
            enableTranscription: configuration.enableTranscription,
            logLevel: configuration.logLevel
        )

        return try await Conversation(
            apiKey: apiKey,
            mode: mode,
            configuration: configWithTurnMode,
            systemMessage: finalSystemMessage,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers,
            toolExecutor: toolExecutor
        )
    }

    // MARK: - Events Stream

    /// Stream of all emitted events
    /// Use this to observe all events sequentially: `for await event in echo.events { ... }`
    ///
    /// ## Usage
    /// ```swift
    /// Task {
    ///     for await event in echo.events {
    ///         switch event {
    ///         case .userStartedSpeaking:
    ///             updateUI()
    ///         case .assistantStoppedSpeaking:
    ///             // Handle response complete
    ///         case .error(let error):
    ///             handleError(error)
    ///         default:
    ///             break
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Note: This creates an async sequence that yields events as they occur.
    ///        You can break out of the loop when done processing events.
    public var events: AsyncStream<EchoEvent> {
        eventEmitter.events
    }

    // MARK: - Tool Registration

    /// Registers a tool/function that can be called by the model
    /// - Parameter tool: The tool to register
    public func registerTool(_ tool: Tool) async {
        tools.append(tool)
        // Also register in the tool executor
        await toolExecutor.register(tool)
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
            toolExecutor: toolExecutor,
            audioCaptureFactory: audioCaptureFactory,
            audioPlaybackFactory: audioPlaybackFactory
        )
    }
}
