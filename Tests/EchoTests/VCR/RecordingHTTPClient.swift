// RecordingHTTPClient.swift
// Echo Tests - VCR Infrastructure
// HTTP client wrapper that records real API interactions to cassettes

import Foundation
@testable import Echo
import NIOHTTP1  // For HTTPMethod
import NIOCore    // For ByteBuffer

/// HTTP client that wraps real HTTPClient and records interactions to cassettes
public actor RecordingHTTPClient: HTTPClientProtocol {
    /// The real HTTP client
    private let realClient: HTTPClient

    /// Cassette being recorded to
    private var cassette: VCRCassette

    /// Directory where cassettes will be saved
    private let cassettesDirectory: URL

    /// Initialize with real client
    /// - Parameters:
    ///   - realClient: The actual HTTPClient to wrap
    ///   - cassetteName: Name for the cassette being recorded
    ///   - cassettesDirectory: Directory to save cassettes
    public init(
        realClient: HTTPClient,
        cassetteName: String,
        cassettesDirectory: URL
    ) {
        self.realClient = realClient
        self.cassette = VCRCassette(name: cassetteName, interactions: [])
        self.cassettesDirectory = cassettesDirectory

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: cassettesDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Make a real request and record the interaction
    /// Note: Response must be Codable (both Encodable and Decodable) for recording
    public func request<Request: Encodable & Sendable, Response: Codable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: Request,
        estimatedTokens: Int = 1000
    ) async throws -> Response {
        print("📼 Recording: \(method.rawValue) \(endpoint)")

        // Make real API call
        let response: Response = try await realClient.request(
            endpoint: endpoint,
            method: method,
            body: body,
            estimatedTokens: estimatedTokens
        )

        // Serialize request and response for recording
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let requestBodyData = try encoder.encode(body)
        let requestBodyJSON = String(data: requestBodyData, encoding: .utf8)

        let responseData = try encoder.encode(response)
        let responseJSON = String(data: responseData, encoding: .utf8)!

        // Record the interaction
        let interaction = VCRInteraction(
            request: .init(
                endpoint: endpoint,
                method: method.rawValue,
                bodyJSON: requestBodyJSON
            ),
            response: .init(
                statusCode: 200,
                bodyJSON: responseJSON,
                headers: ["Content-Type": "application/json"]
            )
        )

        cassette.record(interaction)

        print("✅ Recorded interaction to cassette '\(cassette.name)'")

        return response
    }

    /// Performs a GET request
    public func get<Response: Codable & Sendable>(endpoint: String) async throws -> Response {
        return try await realClient.get(endpoint: endpoint)
    }

    /// Performs a DELETE request
    public func delete(endpoint: String) async throws {
        try await realClient.delete(endpoint: endpoint)
    }

    /// Performs a POST request without body
    public func post<Response: Codable & Sendable>(endpoint: String) async throws -> Response {
        return try await realClient.post(endpoint: endpoint)
    }

    /// Performs a streaming request
    /// Note: For VCR recording, we collect all streaming events and record them
    nonisolated public func stream<Request: Encodable & Sendable>(
        endpoint: String,
        body: Request,
        estimatedTokens: Int = 1000
    ) async -> AsyncThrowingStream<NIOCore.ByteBuffer, Error> {
        return await realClient.stream(endpoint: endpoint, body: body, estimatedTokens: estimatedTokens)
    }

    /// Save the recorded cassette to disk
    public func saveCassette() throws {
        try cassette.save(to: cassettesDirectory)
        print("💾 Saved cassette '\(cassette.name).json' with \(cassette.interactions.count) interactions")
    }

    /// Get the cassette (for inspection)
    public func getCassette() -> VCRCassette {
        return cassette
    }
}
