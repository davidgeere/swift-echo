// EmbeddingsClient.swift
// Echo - Embeddings
// Main client for OpenAI's Embeddings API

import Foundation
import NIOCore

/// Client for interacting with OpenAI's Embeddings API
public actor EmbeddingsClient {
    // MARK: - Properties
    
    /// HTTP client for making requests
    private let httpClient: any HTTPClientProtocol
    
    /// Event emitter for publishing events
    private let eventEmitter: EventEmitter
    
    /// Enable logging
    private let enableLogging: Bool
    
    /// Usage accumulator for tracking costs
    private let usageAccumulator = EmbeddingUsageAccumulator()
    
    // MARK: - Initialization
    
    /// Creates a new Embeddings API client
    /// - Parameters:
    ///   - apiKey: OpenAI API key (provide this OR httpClient)
    ///   - httpClient: HTTP client instance (for dependency injection/testing)
    ///   - eventEmitter: Event emitter for publishing events
    ///   - enableLogging: Whether to enable logging (default: false)
    public init(
        apiKey: String? = nil,
        httpClient: (any HTTPClientProtocol)? = nil,
        eventEmitter: EventEmitter,
        enableLogging: Bool = false
    ) {
        // Use provided httpClient or create default with apiKey
        if let client = httpClient {
            self.httpClient = client
        } else if let key = apiKey {
            self.httpClient = HTTPClient(apiKey: key)
        } else {
            fatalError("EmbeddingsClient requires either apiKey or httpClient")
        }
        
        self.eventEmitter = eventEmitter
        self.enableLogging = enableLogging
    }
    
    // MARK: - Single Embedding
    
    /// Generates an embedding for a single text
    /// - Parameters:
    ///   - text: The text to embed
    ///   - model: The embedding model to use (default: text-embedding-3-small)
    ///   - dimensions: Optional custom dimensions (for models that support it)
    /// - Returns: The embedding vector
    /// - Throws: EchoError if the request fails
    public func generateEmbedding(
        text: String,
        model: EmbeddingModel = .textEmbedding3Small,
        dimensions: Int? = nil
    ) async throws -> EmbeddingVector {
        log("Generating embedding for single text with model: \(model.rawValue)")
        
        // Validate dimensions if provided
        if let dims = dimensions {
            try validateDimensions(dims, for: model)
        }
        
        // Create request
        let request = EmbeddingRequest(
            text: text,
            model: model,
            dimensions: dimensions
        )
        
        // Execute request
        let response = try await executeRequest(request, model: model)
        
        // Extract first embedding
        guard let embedding = response.firstEmbedding else {
            throw EchoError.embeddingError("No embedding returned in response")
        }
        
        log("Generated embedding with \(embedding.count) dimensions")
        
        // Emit event
        await eventEmitter.emit(.embeddingGenerated(
            text: text,
            dimensions: embedding.count,
            model: model.rawValue
        ))
        
        return EmbeddingVector(values: embedding)
    }
    
    // MARK: - Batch Embeddings
    
    /// Generates embeddings for multiple texts
    /// - Parameters:
    ///   - texts: Array of texts to embed
    ///   - model: The embedding model to use (default: text-embedding-3-small)
    ///   - dimensions: Optional custom dimensions (for models that support it)
    /// - Returns: Array of embedding vectors in the same order as input
    /// - Throws: EchoError if the request fails
    public func generateEmbeddings(
        texts: [String],
        model: EmbeddingModel = .textEmbedding3Small,
        dimensions: Int? = nil
    ) async throws -> [EmbeddingVector] {
        guard !texts.isEmpty else {
            throw EchoError.embeddingError("Cannot generate embeddings for empty text array")
        }
        
        log("Generating embeddings for \(texts.count) texts with model: \(model.rawValue)")
        
        // Validate dimensions if provided
        if let dims = dimensions {
            try validateDimensions(dims, for: model)
        }
        
        // OpenAI has a limit on batch size (typically 2048 inputs)
        let maxBatchSize = 2048
        
        if texts.count > maxBatchSize {
            // Split into batches and process
            return try await generateEmbeddingsInBatches(
                texts: texts,
                model: model,
                dimensions: dimensions,
                batchSize: maxBatchSize
            )
        }
        
        // Create request
        let request = EmbeddingRequest(
            texts: texts,
            model: model,
            dimensions: dimensions
        )
        
        // Execute request
        let response = try await executeRequest(request, model: model)
        
        // Extract embeddings in order
        let embeddings = response.embeddings.map { EmbeddingVector(values: $0) }
        
        log("Generated \(embeddings.count) embeddings")
        
        // Emit event
        await eventEmitter.emit(.embeddingsGenerated(
            count: embeddings.count,
            dimensions: embeddings.first?.dimensions ?? 0,
            model: model.rawValue
        ))
        
        return embeddings
    }
    
    // MARK: - Private Methods
    
    /// Executes an embedding request
    private func executeRequest(_ request: EmbeddingRequest, model: EmbeddingModel) async throws -> EmbeddingResponse {
        // Estimate tokens (rough: ~4 chars per token)
        let totalChars = request.input.texts.reduce(0) { $0 + $1.count }
        let estimatedTokens = max(totalChars / 4, 10)
        
        do {
            // Execute HTTP request
            let response: EmbeddingResponse = try await httpClient.request(
                endpoint: "/embeddings",
                method: .POST,
                body: request,
                estimatedTokens: estimatedTokens
            )
            
            // Track usage
            let usage = EmbeddingUsage(from: response.usage, model: model)
            await usageAccumulator.add(usage)
            
            // Log cost if enabled
            if enableLogging, let costString = usage.costString {
                log("Request cost: \(costString) for \(usage.promptTokens) tokens")
            }
            
            // Emit connection status
            await eventEmitter.emit(.connectionStatusChanged(isConnected: true))
            
            return response
            
        } catch let error as HTTPError {
            await eventEmitter.emit(.connectionStatusChanged(isConnected: false))
            throw convertHTTPError(error)
        } catch {
            await eventEmitter.emit(.error(error: error))
            throw EchoError.networkError(error)
        }
    }
    
    /// Generates embeddings in batches for large inputs
    private func generateEmbeddingsInBatches(
        texts: [String],
        model: EmbeddingModel,
        dimensions: Int?,
        batchSize: Int
    ) async throws -> [EmbeddingVector] {
        log("Processing \(texts.count) texts in batches of \(batchSize)")
        
        var allEmbeddings: [EmbeddingVector] = []
        
        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batch = Array(texts[batchStart..<batchEnd])
            
            log("Processing batch \(batchStart/batchSize + 1): texts \(batchStart)-\(batchEnd-1)")
            
            let batchEmbeddings = try await generateEmbeddings(
                texts: batch,
                model: model,
                dimensions: dimensions
            )
            
            allEmbeddings.append(contentsOf: batchEmbeddings)
        }
        
        return allEmbeddings
    }
    
    /// Validates custom dimensions for a model
    private func validateDimensions(_ dimensions: Int, for model: EmbeddingModel) throws {
        guard model.supportsCustomDimensions else {
            throw EchoError.embeddingError(
                "Model \(model.rawValue) does not support custom dimensions"
            )
        }
        
        // Dimensions must be positive and typically <= the model's max dimensions
        guard dimensions > 0 && dimensions <= model.dimensions else {
            throw EchoError.embeddingError(
                "Invalid dimensions \(dimensions) for model \(model.rawValue). " +
                "Must be between 1 and \(model.dimensions)"
            )
        }
    }
    
    /// Converts HTTP error to EchoError
    private func convertHTTPError(_ error: HTTPError) -> Error {
        switch error {
        case .httpStatus(let code):
            switch code {
            case 401:
                return EchoError.authenticationFailed
            case 429:
                return EchoError.rateLimitExceeded(retryAfter: nil)
            case 400:
                return EchoError.invalidRequest("Bad request to embeddings API")
            default:
                return EchoError.httpError(Int(code))
            }
        case .timeout:
            return EchoError.timeout
        case .invalidResponse:
            return EchoError.invalidResponse("Invalid HTTP response from embeddings API")
        }
    }
    
    /// Logs a message if logging is enabled
    private func log(_ message: String) {
        if enableLogging {
            print("[EmbeddingsClient] \(message)")
        }
    }
    
    // MARK: - Usage Tracking
    
    /// Returns the total accumulated usage statistics
    public func getTotalUsage() async -> (tokens: Int, cost: Double, requests: Int) {
        return await usageAccumulator.total
    }
    
    /// Resets the usage accumulator
    public func resetUsage() async {
        await usageAccumulator.reset()
    }
}

// MARK: - Similarity Search Extension

extension EmbeddingsClient {
    /// Finds the most similar texts from a corpus
    /// - Parameters:
    ///   - query: The query text
    ///   - corpus: Array of texts to search through
    ///   - topK: Number of results to return (default: 10)
    ///   - model: The embedding model to use
    /// - Returns: Array of indices and similarity scores, sorted by similarity
    /// - Throws: EchoError if embedding generation fails
    public func findSimilar(
        query: String,
        in corpus: [String],
        topK: Int = 10,
        model: EmbeddingModel = .textEmbedding3Small
    ) async throws -> [(index: Int, text: String, similarity: Float)] {
        guard !corpus.isEmpty else {
            throw EchoError.embeddingError("Cannot search in empty corpus")
        }
        
        log("Finding similar texts in corpus of \(corpus.count) items")
        
        // Generate query embedding
        let queryEmbedding = try await generateEmbedding(text: query, model: model)
        
        // Generate corpus embeddings (batched for efficiency)
        let corpusEmbeddings = try await generateEmbeddings(texts: corpus, model: model)
        
        // Calculate similarities
        let similarities = try corpusEmbeddings.mostSimilar(to: queryEmbedding, topK: topK)
        
        // Map to results with text
        let results = similarities.map { (index: $0.index, text: corpus[$0.index], similarity: $0.similarity) }
        
        log("Found \(results.count) similar texts")
        
        return results
    }
}
