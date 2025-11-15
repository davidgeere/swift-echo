// EmbeddingResponse.swift
// Echo - Models
// Response structure for the Embeddings API

import Foundation

/// Response from the Embeddings API
public struct EmbeddingResponse: Decodable, Sendable {
    /// The object type (always "list")
    public let object: String
    
    /// Array of embedding objects
    public let data: [EmbeddingData]
    
    /// The model used for embedding
    public let model: String
    
    /// Usage information including token counts
    public let usage: EmbeddingUsageInfo
    
    /// Individual embedding data
    public struct EmbeddingData: Decodable, Sendable {
        /// The object type (always "embedding")
        public let object: String
        
        /// The embedding vector
        public let embedding: [Float]
        
        /// The index of the embedding in the list
        public let index: Int
    }
    
    /// Usage information for the embedding request
    public struct EmbeddingUsageInfo: Decodable, Sendable {
        /// Number of tokens used for the prompt
        public let promptTokens: Int
        
        /// Total number of tokens used (same as promptTokens for embeddings)
        public let totalTokens: Int
        
        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
        }
    }
    
    // MARK: - Convenience Properties
    
    /// Returns the first embedding vector (for single text requests)
    public var firstEmbedding: [Float]? {
        return data.first?.embedding
    }
    
    /// Returns all embedding vectors in order
    public var embeddings: [[Float]] {
        return data
            .sorted(by: { $0.index < $1.index })
            .map { $0.embedding }
    }
    
    /// Returns the number of embeddings
    public var count: Int {
        return data.count
    }
    
    /// Returns the dimension of the embeddings
    public var dimensions: Int? {
        return data.first?.embedding.count
    }
}
