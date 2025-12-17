// EchoNamespaces.swift
// Echo - Core
// Conversational API namespaces for better discoverability and readability

import Foundation

// MARK: - Generate Namespace

extension Echo {
    /// Namespace for all generation operations
    public struct Generate {
        private let echo: Echo
        
        init(echo: Echo) {
            self.echo = echo
        }
        
        // MARK: - Embeddings
        
        /// Generate an embedding from text
        /// - Parameters:
        ///   - text: The text to embed
        ///   - model: The embedding model to use (default: text-embedding-3-small)
        ///   - dimensions: Optional custom dimensions (for models that support it)
        /// - Returns: The embedding vector as an array of Float values
        /// - Throws: EchoError if the request fails
        public func embedding(
            from text: String,
            model: EmbeddingModel = .textEmbedding3Small,
            dimensions: Int? = nil
        ) async throws -> [Float] {
            let client = EmbeddingsClient(apiKey: echo.apiKey, eventEmitter: echo.eventEmitter)
            let vector = try await client.generateEmbedding(text: text, model: model, dimensions: dimensions)
            return vector.values
        }
        
        /// Generate embeddings from multiple texts
        /// - Parameters:
        ///   - texts: Array of texts to embed
        ///   - model: The embedding model to use (default: text-embedding-3-small)
        ///   - dimensions: Optional custom dimensions (for models that support it)
        /// - Returns: Array of embedding vectors in the same order as input
        /// - Throws: EchoError if the request fails
        public func embeddings(
            from texts: [String],
            model: EmbeddingModel = .textEmbedding3Small,
            dimensions: Int? = nil
        ) async throws -> [[Float]] {
            let client = EmbeddingsClient(apiKey: echo.apiKey, eventEmitter: echo.eventEmitter)
            let vectors = try await client.generateEmbeddings(texts: texts, model: model, dimensions: dimensions)
            return vectors.map { $0.values }
        }
        
        // MARK: - Structured Output
        //
        // Note: Structured outputs require the Responses API which is not included
        // in the Realtime-only branch. These methods will throw an error.
        // For structured outputs, use the full Echo library with Responses API support.
        
        /// Generate structured output from a prompt
        ///
        /// - Warning: Structured outputs are not supported in Realtime-only mode.
        ///   The Realtime API does not support structured outputs/JSON schemas.
        ///
        /// - Parameters:
        ///   - type: The Codable type to generate
        ///   - prompt: The prompt to send to the model
        ///   - model: The model to use (defaults to configuration default)
        ///   - instructions: Optional system instructions
        /// - Returns: Decoded instance of the specified type
        /// - Throws: EchoError.unsupportedFeature in Realtime-only mode
        @available(*, unavailable, message: "Structured outputs require Responses API. Use full Echo library for this feature.")
        public func structured<T: Codable & Sendable>(
            _ type: T.Type,
            from prompt: String,
            model: ResponsesModel? = nil,
            instructions: String? = nil
        ) async throws -> T {
            fatalError("Structured outputs not available in Realtime-only mode")
        }
        
        /// Generate structured JSON from a prompt with a custom schema
        ///
        /// - Warning: Structured outputs are not supported in Realtime-only mode.
        ///   The Realtime API does not support structured outputs/JSON schemas.
        ///
        /// - Parameters:
        ///   - jsonSchema: Custom JSON schema definition
        ///   - prompt: The prompt to send to the model
        ///   - model: The model to use (defaults to configuration default)
        ///   - instructions: Optional system instructions
        /// - Returns: Raw JSON string
        /// - Throws: EchoError.unsupportedFeature in Realtime-only mode
        @available(*, unavailable, message: "Structured outputs require Responses API. Use full Echo library for this feature.")
        public func structuredJSON(
            schema jsonSchema: JSONSchema,
            from prompt: String,
            model: ResponsesModel? = nil,
            instructions: String? = nil
        ) async throws -> String {
            fatalError("Structured outputs not available in Realtime-only mode")
        }
    }
    
    /// Access generation operations
    public var generate: Generate {
        return Generate(echo: self)
    }
}

// MARK: - Find Namespace

extension Echo {
    /// Namespace for all search and similarity operations
    public struct Find {
        private let echo: Echo
        
        init(echo: Echo) {
            self.echo = echo
        }
        
        /// Find similar texts from a corpus
        /// - Parameters:
        ///   - query: The query text to search for
        ///   - corpus: Array of texts to search through
        ///   - topK: Number of results to return (default: 10)
        ///   - model: The embedding model to use (default: text-embedding-3-small)
        /// - Returns: Array of (index, text, similarity) tuples, sorted by similarity
        /// - Throws: EchoError if embedding generation fails
        public func similar(
            to query: String,
            in corpus: [String],
            topK: Int = 10,
            model: EmbeddingModel = .textEmbedding3Small
        ) async throws -> [(index: Int, text: String, similarity: Float)] {
            let client = EmbeddingsClient(apiKey: echo.apiKey, eventEmitter: echo.eventEmitter)
            return try await client.findSimilar(query: query, in: corpus, topK: topK, model: model)
        }
        
        /// Find the nearest texts to a query (alias for similar)
        /// - Parameters:
        ///   - query: The query text
        ///   - corpus: Array of texts to search through
        ///   - count: Number of results to return (default: 10)
        ///   - model: The embedding model to use
        /// - Returns: Array of (index, text, similarity) tuples
        /// - Throws: EchoError if embedding generation fails
        public func nearest(
            to query: String,
            in corpus: [String],
            count: Int = 10,
            model: EmbeddingModel = .textEmbedding3Small
        ) async throws -> [(index: Int, text: String, similarity: Float)] {
            return try await similar(to: query, in: corpus, topK: count, model: model)
        }
    }
    
    /// Access search operations
    public var find: Find {
        return Find(echo: self)
    }
}

// MARK: - Start Namespace

extension Echo {
    /// Namespace for initialization operations
    public struct Start {
        private let echo: Echo
        
        init(echo: Echo) {
            self.echo = echo
        }
        
        /// Start a new conversation
        /// - Parameters:
        ///   - mode: The initial mode (audio or text)
        ///   - systemMessage: Optional system instructions for the model
        /// - Returns: A Conversation instance for managing the conversation
        /// - Throws: EchoError if conversation cannot be started
        public func conversation(
            mode: EchoMode,
            with systemMessage: String? = nil
        ) async throws -> Conversation {
            return try await echo.startConversation(
                mode: mode,
                systemMessage: systemMessage
            )
        }
        
        /// Start a new conversation with specific turn mode
        /// - Parameters:
        ///   - mode: The initial mode (audio or text)
        ///   - turnMode: Turn detection mode (overrides configuration default)
        ///   - systemMessage: Optional system instructions
        /// - Returns: A Conversation instance
        /// - Throws: EchoError if conversation cannot be started
        public func conversation(
            mode: EchoMode,
            turnMode: TurnDetection,
            with systemMessage: String? = nil
        ) async throws -> Conversation {
            return try await echo.startConversation(
                mode: mode,
                turnMode: turnMode,
                systemMessage: systemMessage
            )
        }
    }
    
    /// Access initialization operations
    public var start: Start {
        return Start(echo: self)
    }
}

// MARK: - Send Namespace (for Conversation)

extension Conversation {
    /// Namespace for sending operations
    @MainActor
    public struct Send {
        private let conversation: Conversation
        
        init(conversation: Conversation) {
            self.conversation = conversation
        }
        
        /// Send a text message via the Realtime API
        ///
        /// The response will come through events, not as a return value.
        /// In audio mode, the response will be spoken. In text mode, it will be text-only.
        ///
        /// - Parameter text: The message text
        /// - Returns: nil (responses come through events)
        /// - Throws: EchoError if sending fails
        @discardableResult
        public func message(_ text: String) async throws -> Message? {
            return try await conversation.send(text)
        }
        
        // MARK: - Structured Outputs (Not Available)
        //
        // Note: The following methods are unavailable in Realtime-only mode
        // because the Realtime API does not support structured outputs.
        
        /// Send a message with response format
        /// - Warning: Not available in Realtime-only mode.
        @available(*, unavailable, message: "Structured outputs require Responses API. Use full Echo library for this feature.")
        public func message(
            _ text: String,
            expecting format: ResponseFormat
        ) async throws -> Message? {
            fatalError("Structured outputs not available in Realtime-only mode")
        }
        
        /// Send a message expecting JSON output
        /// - Warning: Not available in Realtime-only mode.
        @available(*, unavailable, message: "Structured outputs require Responses API. Use full Echo library for this feature.")
        public func json(_ text: String) async throws -> Message? {
            fatalError("Structured outputs not available in Realtime-only mode")
        }
        
        /// Send a message expecting structured output
        /// - Warning: Not available in Realtime-only mode.
        @available(*, unavailable, message: "Structured outputs require Responses API. Use full Echo library for this feature.")
        public func structured(
            _ text: String,
            schema: JSONSchema
        ) async throws -> Message? {
            fatalError("Structured outputs not available in Realtime-only mode")
        }
    }
    
    /// Access send operations
    public var send: Send {
        return Send(conversation: self)
    }
}

// MARK: - Switch Namespace (for Conversation)

extension Conversation {
    /// Namespace for mode switching operations
    @MainActor
    public struct Switch {
        private let conversation: Conversation
        
        init(conversation: Conversation) {
            self.conversation = conversation
        }
        
        /// Switch to a different mode using function call syntax
        /// - Parameter mode: The new mode to switch to
        /// - Throws: EchoError if switch fails
        /// - Note: Use `conversation.switch(to: .text)` or `conversation.switch(to: .audio)`
        public func callAsFunction(to mode: EchoMode) async throws {
            try await conversation.switchMode(to: mode)
        }
        
        /// Switch to a different mode (alternative syntax)
        /// - Parameter mode: The new mode
        /// - Throws: EchoError if switch fails
        public func to(_ mode: EchoMode) async throws {
            try await conversation.switchMode(to: mode)
        }
    }
    
    /// Access switch operations
    public var `switch`: Switch {
        return Switch(conversation: self)
    }
}

// MARK: - Convenience Type Aliases

extension Echo {
    /// Quick access to embedding operations (alternative syntax)
    public var embeddings: Generate {
        return generate
    }
    
    /// Quick access to search operations (alternative syntax)
    public var search: Find {
        return find
    }
}
