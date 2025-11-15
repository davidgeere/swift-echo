// EmbeddingUsage.swift
// Echo - Embeddings
// Token usage tracking for embedding requests

import Foundation

/// Tracks token usage for embedding operations
public struct EmbeddingUsage: Sendable {
    /// Number of tokens in the input text(s)
    public let promptTokens: Int
    
    /// Total tokens used (same as promptTokens for embeddings)
    public let totalTokens: Int
    
    /// Estimated cost based on model pricing
    public let estimatedCost: Double?
    
    /// Creates embedding usage information
    /// - Parameters:
    ///   - promptTokens: Number of input tokens
    ///   - model: The model used (for cost calculation)
    public init(promptTokens: Int, model: EmbeddingModel? = nil) {
        self.promptTokens = promptTokens
        self.totalTokens = promptTokens
        
        // Calculate estimated cost based on model
        if let model = model {
            self.estimatedCost = Self.calculateCost(tokens: promptTokens, model: model)
        } else {
            self.estimatedCost = nil
        }
    }
    
    /// Creates usage from API response
    internal init(from response: EmbeddingResponse.EmbeddingUsageInfo, model: EmbeddingModel? = nil) {
        self.promptTokens = response.promptTokens
        self.totalTokens = response.totalTokens
        
        if let model = model {
            self.estimatedCost = Self.calculateCost(tokens: response.promptTokens, model: model)
        } else {
            self.estimatedCost = nil
        }
    }
    
    /// Calculates estimated cost based on OpenAI pricing
    /// - Parameters:
    ///   - tokens: Number of tokens
    ///   - model: The embedding model used
    /// - Returns: Estimated cost in USD
    private static func calculateCost(tokens: Int, model: EmbeddingModel) -> Double {
        // Pricing per 1M tokens (as of 2025)
        let pricePerMillionTokens: Double
        
        switch model {
        case .textEmbedding3Small:
            pricePerMillionTokens = 0.02  // $0.020 per 1M tokens
        case .textEmbedding3Large:
            pricePerMillionTokens = 0.13  // $0.130 per 1M tokens
        case .textEmbeddingAda002:
            pricePerMillionTokens = 0.10  // $0.100 per 1M tokens (legacy pricing)
        }
        
        return (Double(tokens) / 1_000_000.0) * pricePerMillionTokens
    }
    
    /// Returns a human-readable cost string
    public var costString: String? {
        guard let cost = estimatedCost else { return nil }
        
        if cost < 0.01 {
            return String(format: "$%.6f", cost)
        } else if cost < 1.0 {
            return String(format: "$%.4f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }
}

// MARK: - Accumulator for Multiple Requests

/// Accumulates usage across multiple embedding requests
public actor EmbeddingUsageAccumulator {
    private var totalPromptTokens: Int = 0
    private var totalCost: Double = 0
    private var requestCount: Int = 0
    
    /// Adds usage from a request
    public func add(_ usage: EmbeddingUsage) {
        totalPromptTokens += usage.promptTokens
        if let cost = usage.estimatedCost {
            totalCost += cost
        }
        requestCount += 1
    }
    
    /// Returns the total accumulated usage
    public var total: (tokens: Int, cost: Double, requests: Int) {
        return (totalPromptTokens, totalCost, requestCount)
    }
    
    /// Resets the accumulator
    public func reset() {
        totalPromptTokens = 0
        totalCost = 0
        requestCount = 0
    }
}
