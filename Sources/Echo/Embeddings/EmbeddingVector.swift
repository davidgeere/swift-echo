// EmbeddingVector.swift
// Echo - Embeddings
// Vector representation for embeddings with utility functions

import Foundation

/// Represents an embedding vector with utilities for similarity calculations
public struct EmbeddingVector: Sendable {
    /// The raw vector values
    public let values: [Float]
    
    /// The dimension of the vector
    public var dimensions: Int {
        return values.count
    }
    
    /// Creates an embedding vector
    /// - Parameter values: The vector values
    public init(values: [Float]) {
        self.values = values
    }
    
    // MARK: - Similarity Calculations
    
    /// Calculates the cosine similarity between this vector and another
    /// - Parameter other: The other vector to compare with
    /// - Returns: Cosine similarity value between -1 and 1 (1 = identical, 0 = orthogonal, -1 = opposite)
    /// - Throws: EchoError if vectors have different dimensions
    public func cosineSimilarity(with other: EmbeddingVector) throws -> Float {
        guard dimensions == other.dimensions else {
            throw EchoError.embeddingError(
                "Cannot calculate similarity between vectors of different dimensions: \(dimensions) vs \(other.dimensions)"
            )
        }
        
        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        
        for i in 0..<dimensions {
            dotProduct += values[i] * other.values[i]
            magnitudeA += values[i] * values[i]
            magnitudeB += other.values[i] * other.values[i]
        }
        
        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        guard magnitude > 0 else { return 0 }
        
        return dotProduct / magnitude
    }
    
    /// Calculates the Euclidean distance between this vector and another
    /// - Parameter other: The other vector to compare with
    /// - Returns: Euclidean distance (0 = identical, larger values = more different)
    /// - Throws: EchoError if vectors have different dimensions
    public func euclideanDistance(to other: EmbeddingVector) throws -> Float {
        guard dimensions == other.dimensions else {
            throw EchoError.embeddingError(
                "Cannot calculate distance between vectors of different dimensions: \(dimensions) vs \(other.dimensions)"
            )
        }
        
        var sumSquaredDifferences: Float = 0
        
        for i in 0..<dimensions {
            let diff = values[i] - other.values[i]
            sumSquaredDifferences += diff * diff
        }
        
        return sqrt(sumSquaredDifferences)
    }
    
    /// Calculates the dot product between this vector and another
    /// - Parameter other: The other vector
    /// - Returns: Dot product value
    /// - Throws: EchoError if vectors have different dimensions
    public func dotProduct(with other: EmbeddingVector) throws -> Float {
        guard dimensions == other.dimensions else {
            throw EchoError.embeddingError(
                "Cannot calculate dot product between vectors of different dimensions: \(dimensions) vs \(other.dimensions)"
            )
        }
        
        var product: Float = 0
        for i in 0..<dimensions {
            product += values[i] * other.values[i]
        }
        return product
    }
    
    /// Returns the magnitude (length) of the vector
    public var magnitude: Float {
        return sqrt(values.reduce(0) { $0 + $1 * $1 })
    }
    
    /// Returns a normalized (unit) vector
    public var normalized: EmbeddingVector {
        let mag = magnitude
        guard mag > 0 else { return self }
        return EmbeddingVector(values: values.map { $0 / mag })
    }
}

// MARK: - Array Extension for Multiple Vectors

public extension Array where Element == EmbeddingVector {
    /// Finds the vectors most similar to a query vector
    /// - Parameters:
    ///   - query: The query vector
    ///   - topK: Number of results to return
    /// - Returns: Array of indices and similarity scores, sorted by similarity (highest first)
    func mostSimilar(to query: EmbeddingVector, topK: Int = 10) throws -> [(index: Int, similarity: Float)] {
        var similarities: [(index: Int, similarity: Float)] = []
        
        for (index, vector) in self.enumerated() {
            let similarity = try vector.cosineSimilarity(with: query)
            similarities.append((index: index, similarity: similarity))
        }
        
        return similarities
            .sorted(by: { $0.similarity > $1.similarity })
            .prefix(topK)
            .map { $0 }
    }
    
    /// Returns the average (centroid) of all vectors
    /// - Throws: EchoError if array is empty or vectors have different dimensions
    var centroid: EmbeddingVector {
        get throws {
            guard !isEmpty else {
                throw EchoError.embeddingError("Cannot calculate centroid of empty vector array")
            }
            
            let dimensions = first!.dimensions
            guard allSatisfy({ $0.dimensions == dimensions }) else {
                throw EchoError.embeddingError("All vectors must have the same dimensions to calculate centroid")
            }
            
            var sumVector = [Float](repeating: 0, count: dimensions)
            
            for vector in self {
                for i in 0..<dimensions {
                    sumVector[i] += vector.values[i]
                }
            }
            
            let count = Float(self.count)
            let averageVector = sumVector.map { $0 / count }
            
            return EmbeddingVector(values: averageVector)
        }
    }
}
