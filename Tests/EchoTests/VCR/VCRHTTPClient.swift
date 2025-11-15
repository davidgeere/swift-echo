// VCRHTTPClient.swift
// Echo Tests - VCR Infrastructure
// Mock HTTP client that plays back recorded cassettes

import Foundation
import AsyncHTTPClient
import NIOHTTP1
@testable import Echo

// MARK: - Helper Types

/// Empty request body for GET/DELETE/POST requests without payload
private struct EmptyRequestBody: Encodable {
    init() {}
}

/// Empty response body for DELETE requests
private struct EmptyResponseBody: Decodable {}

/// Mock HTTP client that replays recorded interactions from VCR cassettes
public actor VCRHTTPClient: HTTPClientProtocol {
    /// The cassette being played back
    private let cassette: VCRCassette

    /// Whether to throw if interaction not found (strict mode)
    private let strict: Bool

    /// Base URL for API
    private let baseURL: String

    /// Initialize with a cassette
    /// - Parameters:
    ///   - cassette: Cassette to playback
    ///   - strict: If true, throw error when interaction not found. If false, return empty response.
    ///   - baseURL: Base URL for the API (default: OpenAI)
    public init(cassette: VCRCassette, strict: Bool = true, baseURL: String = "https://api.openai.com/v1") {
        self.cassette = cassette
        self.strict = strict
        self.baseURL = baseURL
    }

    /// Make a request by finding matching interaction in cassette
    public func request<Request: Encodable, Response: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Request,
        estimatedTokens: Int = 1000
    ) async throws -> Response {
        // Serialize request body to JSON for matching
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bodyData = try encoder.encode(body)
        let bodyJSON = String(data: bodyData, encoding: .utf8)

        // Find matching interaction
        guard let interaction = cassette.findInteraction(
            endpoint: endpoint,
            method: method.rawValue,
            bodyJSON: bodyJSON
        ) else {
            if strict {
                throw VCRError.interactionNotFound(
                    endpoint: endpoint,
                    method: method.rawValue,
                    cassette: cassette.name
                )
            } else {
                // Return mock empty response in non-strict mode
                throw VCRError.interactionNotFound(
                    endpoint: endpoint,
                    method: method.rawValue,
                    cassette: cassette.name
                )
            }
        }

        // Decode response from cassette
        guard let responseData = interaction.response.bodyJSON.data(using: .utf8) else {
            throw VCRError.invalidResponseData(cassette: cassette.name)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(Response.self, from: responseData)
    }

    /// Performs a GET request
    public func get<Response: Decodable>(endpoint: String) async throws -> Response {
        return try await request(endpoint: endpoint, method: .GET, body: EmptyRequestBody(), estimatedTokens: 100)
    }

    /// Performs a DELETE request
    public func delete(endpoint: String) async throws {
        let _: EmptyResponseBody = try await request(endpoint: endpoint, method: .DELETE, body: EmptyRequestBody(), estimatedTokens: 100)
    }

    /// Performs a POST request without body
    public func post<Response: Decodable>(endpoint: String) async throws -> Response {
        return try await request(endpoint: endpoint, method: .POST, body: EmptyRequestBody(), estimatedTokens: 100)
    }
}

/// VCR-specific errors
public enum VCRError: Error, CustomStringConvertible {
    case interactionNotFound(endpoint: String, method: String, cassette: String)
    case invalidResponseData(cassette: String)
    case cassetteNotFound(name: String)

    public var description: String {
        switch self {
        case .interactionNotFound(let endpoint, let method, let cassette):
            return """
            VCR: No recorded interaction found
            Cassette: \(cassette)
            Request: \(method) \(endpoint)

            Hint: Run test in RECORD mode to capture this interaction
            """
        case .invalidResponseData(let cassette):
            return "VCR: Invalid response data in cassette '\(cassette)'"
        case .cassetteNotFound(let name):
            return "VCR: Cassette '\(name)' not found. Run in RECORD mode first."
        }
    }
}
