// HTTPClientProtocol.swift
// Echo Tests - VCR Infrastructure
// Protocol abstraction for HTTP clients to enable VCR recording/playback

import Foundation
@testable import Echo
import NIOHTTP1  // For HTTPMethod

/// Protocol that HTTPClient conforms to, allowing VCR mocking
/// NOTE: We require Response to be Codable (not just Decodable) to support recording
public protocol HTTPClientProtocol: Actor {
    /// Make an HTTP request with encoded body
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - method: HTTP method
    ///   - body: Encodable request body
    ///   - estimatedTokens: Estimated tokens for rate limiting
    /// - Returns: Decoded response
    func request<Request: Encodable & Sendable, Response: Codable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: Request,
        estimatedTokens: Int
    ) async throws -> Response

    /// Performs a GET request
    func get<Response: Codable & Sendable>(endpoint: String) async throws -> Response

    /// Performs a DELETE request
    func delete(endpoint: String) async throws

    /// Performs a POST request without body
    func post<Response: Codable & Sendable>(endpoint: String) async throws -> Response
}

/// Make Echo's HTTPClient conform to the protocol
extension HTTPClient: HTTPClientProtocol {}
