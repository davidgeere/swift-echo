// EmbeddingRequest.swift
// Echo - Models
// Request structure for the Embeddings API

import Foundation

/// Request structure for creating embeddings
public struct EmbeddingRequest: Encodable, Sendable {
    /// Input text to embed, encoded as a string or array of strings
    public let input: Input
    
    /// ID of the model to use
    public let model: String
    
    /// The format to return the embeddings in (can be "float" or "base64")
    public let encodingFormat: String?
    
    /// The number of dimensions the resulting output embeddings should have (for models that support it)
    public let dimensions: Int?
    
    /// A unique identifier representing your end-user
    public let user: String?
    
    /// Input can be a single string or array of strings
    public enum Input: Encodable, Sendable {
        case single(String)
        case batch([String])
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .single(let text):
                try container.encode(text)
            case .batch(let texts):
                try container.encode(texts)
            }
        }
        
        /// Returns the text array regardless of input type
        public var texts: [String] {
            switch self {
            case .single(let text):
                return [text]
            case .batch(let texts):
                return texts
            }
        }
        
        /// Returns the count of texts
        public var count: Int {
            switch self {
            case .single:
                return 1
            case .batch(let texts):
                return texts.count
            }
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case input
        case model
        case encodingFormat = "encoding_format"
        case dimensions
        case user
    }
    
    /// Creates an embedding request for a single text
    /// - Parameters:
    ///   - text: The text to embed
    ///   - model: The embedding model to use
    ///   - encodingFormat: Optional encoding format (default: "float")
    ///   - dimensions: Optional custom dimensions (for models that support it)
    ///   - user: Optional user identifier
    public init(
        text: String,
        model: EmbeddingModel,
        encodingFormat: String? = "float",
        dimensions: Int? = nil,
        user: String? = nil
    ) {
        self.input = .single(text)
        self.model = model.rawValue
        self.encodingFormat = encodingFormat
        self.dimensions = dimensions
        self.user = user
    }
    
    /// Creates an embedding request for multiple texts
    /// - Parameters:
    ///   - texts: Array of texts to embed
    ///   - model: The embedding model to use
    ///   - encodingFormat: Optional encoding format (default: "float")
    ///   - dimensions: Optional custom dimensions (for models that support it)
    ///   - user: Optional user identifier
    public init(
        texts: [String],
        model: EmbeddingModel,
        encodingFormat: String? = "float",
        dimensions: Int? = nil,
        user: String? = nil
    ) {
        self.input = .batch(texts)
        self.model = model.rawValue
        self.encodingFormat = encodingFormat
        self.dimensions = dimensions
        self.user = user
    }
}
