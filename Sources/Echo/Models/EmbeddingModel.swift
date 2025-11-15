// EmbeddingModel.swift
// Echo - Models
// Supported embedding models for the Embeddings API

import Foundation

/// Supported OpenAI embedding models
public enum EmbeddingModel: String, CaseIterable, Codable, Sendable {
    /// text-embedding-3-small: Most cost-effective model (1536 dimensions)
    case textEmbedding3Small = "text-embedding-3-small"
    
    /// text-embedding-3-large: Higher quality embeddings (3072 dimensions)
    case textEmbedding3Large = "text-embedding-3-large"
    
    /// text-embedding-ada-002: Legacy model (1536 dimensions) - maintained for compatibility
    case textEmbeddingAda002 = "text-embedding-ada-002"
    
    /// Returns the dimension count for this embedding model
    public var dimensions: Int {
        switch self {
        case .textEmbedding3Small:
            return 1536
        case .textEmbedding3Large:
            return 3072
        case .textEmbeddingAda002:
            return 1536
        }
    }
    
    /// Returns whether this model supports custom dimensions
    public var supportsCustomDimensions: Bool {
        switch self {
        case .textEmbedding3Small, .textEmbedding3Large:
            return true
        case .textEmbeddingAda002:
            return false
        }
    }
    
    /// Returns a human-readable description of the model
    public var description: String {
        switch self {
        case .textEmbedding3Small:
            return "Optimized embedding model with 1536 dimensions"
        case .textEmbedding3Large:
            return "High-quality embedding model with 3072 dimensions"
        case .textEmbeddingAda002:
            return "Legacy embedding model with 1536 dimensions"
        }
    }
    
    /// Validates that the model string is a supported embedding model
    /// - Parameter modelString: The model string to validate
    /// - Returns: The validated EmbeddingModel
    /// - Throws: EchoError if the model is not supported
    public static func validate(_ modelString: String) throws -> EmbeddingModel {
        guard let model = EmbeddingModel(rawValue: modelString) else {
            throw EchoError.unsupportedModel(
                "Model '\(modelString)' is not a supported embedding model. " +
                "Valid models: text-embedding-3-small, text-embedding-3-large, text-embedding-ada-002"
            )
        }
        return model
    }
}

// MARK: - Default Model

extension EmbeddingModel {
    /// The default embedding model (text-embedding-3-small for cost efficiency)
    public static let `default` = EmbeddingModel.textEmbedding3Small
}
