// EmbeddingsAPITests.swift
// Echo Tests
// Unit tests for the Embeddings API functionality

import Testing
import Foundation
@testable import Echo

@Suite("Embeddings API Tests")
struct EmbeddingsAPITests {
    
    // MARK: - Model Tests
    
    @Test("Embedding model validation")
    func testEmbeddingModelValidation() throws {
        // Valid models
        let small = try EmbeddingModel.validate("text-embedding-3-small")
        #expect(small == .textEmbedding3Small)
        
        let large = try EmbeddingModel.validate("text-embedding-3-large")
        #expect(large == .textEmbedding3Large)
        
        let ada = try EmbeddingModel.validate("text-embedding-ada-002")
        #expect(ada == .textEmbeddingAda002)
        
        // Invalid model
        #expect(throws: EchoError.self) {
            _ = try EmbeddingModel.validate("gpt-4")
        }
    }
    
    @Test("Embedding model dimensions")
    func testEmbeddingModelDimensions() {
        #expect(EmbeddingModel.textEmbedding3Small.dimensions == 1536)
        #expect(EmbeddingModel.textEmbedding3Large.dimensions == 3072)
        #expect(EmbeddingModel.textEmbeddingAda002.dimensions == 1536)
    }
    
    @Test("Embedding model custom dimensions support")
    func testCustomDimensionsSupport() {
        #expect(EmbeddingModel.textEmbedding3Small.supportsCustomDimensions == true)
        #expect(EmbeddingModel.textEmbedding3Large.supportsCustomDimensions == true)
        #expect(EmbeddingModel.textEmbeddingAda002.supportsCustomDimensions == false)
    }
    
    // MARK: - Request Tests
    
    @Test("Single text embedding request")
    func testSingleTextEmbeddingRequest() throws {
        let request = EmbeddingRequest(
            text: "Hello, world!",
            model: .textEmbedding3Small,
            dimensions: 256
        )
        
        #expect(request.model == "text-embedding-3-small")
        #expect(request.dimensions == 256)
        #expect(request.input.count == 1)
        #expect(request.input.texts == ["Hello, world!"])
    }
    
    @Test("Batch embedding request")
    func testBatchEmbeddingRequest() throws {
        let texts = ["First text", "Second text", "Third text"]
        let request = EmbeddingRequest(
            texts: texts,
            model: .textEmbedding3Large
        )
        
        #expect(request.model == "text-embedding-3-large")
        #expect(request.input.count == 3)
        #expect(request.input.texts == texts)
    }
    
    // MARK: - Vector Tests
    
    @Test("Embedding vector cosine similarity")
    func testCosineSimilarity() throws {
        // Create two identical vectors
        let vector1 = EmbeddingVector(values: [1.0, 0.5, 0.3])
        let vector2 = EmbeddingVector(values: [1.0, 0.5, 0.3])
        
        let similarity = try vector1.cosineSimilarity(with: vector2)
        #expect(similarity == 1.0) // Identical vectors have similarity 1.0
        
        // Create orthogonal vectors
        let vector3 = EmbeddingVector(values: [1.0, 0.0])
        let vector4 = EmbeddingVector(values: [0.0, 1.0])
        
        let orthogonalSimilarity = try vector3.cosineSimilarity(with: vector4)
        #expect(abs(orthogonalSimilarity) < 0.001) // Orthogonal vectors have similarity ~0
    }
    
    @Test("Embedding vector euclidean distance")
    func testEuclideanDistance() throws {
        // Same vectors have distance 0
        let vector1 = EmbeddingVector(values: [1.0, 2.0, 3.0])
        let vector2 = EmbeddingVector(values: [1.0, 2.0, 3.0])
        
        let distance = try vector1.euclideanDistance(to: vector2)
        #expect(distance == 0.0)
        
        // Different vectors have positive distance
        let vector3 = EmbeddingVector(values: [0.0, 0.0, 0.0])
        let vector4 = EmbeddingVector(values: [3.0, 4.0, 0.0])
        
        let distance2 = try vector3.euclideanDistance(to: vector4)
        #expect(distance2 == 5.0) // 3-4-5 right triangle
    }
    
    @Test("Embedding vector normalization")
    func testVectorNormalization() {
        let vector = EmbeddingVector(values: [3.0, 4.0])
        let normalized = vector.normalized
        
        // Normalized vector should have magnitude 1
        #expect(abs(normalized.magnitude - 1.0) < 0.001)
        
        // Direction should be preserved
        let ratio = normalized.values[1] / normalized.values[0]
        #expect(abs(ratio - (4.0/3.0)) < 0.001)
    }
    
    @Test("Vector dimension mismatch error")
    func testDimensionMismatch() throws {
        let vector1 = EmbeddingVector(values: [1.0, 2.0])
        let vector2 = EmbeddingVector(values: [1.0, 2.0, 3.0])
        
        #expect(throws: EchoError.self) {
            _ = try vector1.cosineSimilarity(with: vector2)
        }
        
        #expect(throws: EchoError.self) {
            _ = try vector1.euclideanDistance(to: vector2)
        }
    }
    
    // MARK: - Array Extension Tests
    
    @Test("Find most similar vectors")
    func testMostSimilarVectors() throws {
        let vectors = [
            EmbeddingVector(values: [1.0, 0.0, 0.0]),
            EmbeddingVector(values: [0.9, 0.1, 0.0]),
            EmbeddingVector(values: [0.0, 1.0, 0.0]),
            EmbeddingVector(values: [0.0, 0.0, 1.0])
        ]
        
        let query = EmbeddingVector(values: [1.0, 0.0, 0.0])
        let similar = try vectors.mostSimilar(to: query, topK: 2)
        
        #expect(similar.count == 2)
        #expect(similar[0].index == 0) // First vector is identical
        #expect(similar[0].similarity == 1.0)
        #expect(similar[1].index == 1) // Second vector is very similar
    }
    
    @Test("Calculate vector centroid")
    func testVectorCentroid() throws {
        let vectors = [
            EmbeddingVector(values: [0.0, 0.0]),
            EmbeddingVector(values: [2.0, 0.0]),
            EmbeddingVector(values: [2.0, 2.0]),
            EmbeddingVector(values: [0.0, 2.0])
        ]
        
        let centroid = try vectors.centroid
        #expect(centroid.values[0] == 1.0) // Average of 0,2,2,0
        #expect(centroid.values[1] == 1.0) // Average of 0,0,2,2
    }
    
    // MARK: - Usage Tracking Tests
    
    @Test("Embedding usage calculation")
    func testUsageCalculation() {
        let usage = EmbeddingUsage(promptTokens: 100, model: .textEmbedding3Small)
        
        #expect(usage.promptTokens == 100)
        #expect(usage.totalTokens == 100)
        #expect(usage.estimatedCost != nil)
        
        // Check cost calculation (at $0.02 per 1M tokens)
        if let cost = usage.estimatedCost {
            let expectedCost = (100.0 / 1_000_000.0) * 0.02
            #expect(abs(cost - expectedCost) < 0.000001)
        }
    }
    
    @Test("Usage accumulator")
    func testUsageAccumulator() async {
        let accumulator = EmbeddingUsageAccumulator()
        
        let usage1 = EmbeddingUsage(promptTokens: 100, model: .textEmbedding3Small)
        let usage2 = EmbeddingUsage(promptTokens: 200, model: .textEmbedding3Large)
        
        await accumulator.add(usage1)
        await accumulator.add(usage2)
        
        let total = await accumulator.total
        #expect(total.tokens == 300)
        #expect(total.requests == 2)
        
        // Reset and verify
        await accumulator.reset()
        let resetTotal = await accumulator.total
        #expect(resetTotal.tokens == 0)
        #expect(resetTotal.requests == 0)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Invalid dimensions error")
    func testInvalidDimensionsError() async throws {
        let eventEmitter = EventEmitter()
        let client = EmbeddingsClient(
            apiKey: "test-key",
            eventEmitter: eventEmitter
        )
        
        // Ada-002 doesn't support custom dimensions
        await #expect(throws: EchoError.self) {
            _ = try await client.generateEmbedding(
                text: "Test",
                model: .textEmbeddingAda002,
                dimensions: 512
            )
        }
    }
    
    @Test("Empty text array error")
    func testEmptyTextArrayError() async throws {
        let eventEmitter = EventEmitter()
        let client = EmbeddingsClient(
            apiKey: "test-key",
            eventEmitter: eventEmitter
        )
        
        await #expect(throws: EchoError.self) {
            _ = try await client.generateEmbeddings(
                texts: [],
                model: .textEmbedding3Small
            )
        }
    }
}

// MARK: - Echo API Integration Tests

@Suite("Echo Embeddings Integration Tests")
struct EchoEmbeddingsIntegrationTests {
    
    @Test("Echo generateEmbedding method")
    func testEchoGenerateEmbedding() async throws {
        let echo = Echo(key: "test-key")
        
        // This will fail with network error in tests (no actual API key)
        // but validates the API structure
        do {
            _ = try await echo.generateEmbedding(
                text: "Test text",
                model: .textEmbedding3Small
            )
        } catch {
            // Expected to fail without real API key
            #expect(error is EchoError)
        }
    }
    
    @Test("Echo generateEmbeddings batch method")
    func testEchoGenerateEmbeddings() async throws {
        let echo = Echo(key: "test-key")
        
        do {
            _ = try await echo.generateEmbeddings(
                texts: ["Text 1", "Text 2"],
                model: .textEmbedding3Large
            )
        } catch {
            // Expected to fail without real API key
            #expect(error is EchoError)
        }
    }
    
    @Test("Echo findSimilarTexts method")
    func testEchoFindSimilarTexts() async throws {
        let echo = Echo(key: "test-key")
        
        do {
            _ = try await echo.findSimilarTexts(
                query: "Query text",
                in: ["Doc 1", "Doc 2", "Doc 3"],
                topK: 2,
                model: .textEmbedding3Small
            )
        } catch {
            // Expected to fail without real API key
            #expect(error is EchoError)
        }
    }
}
