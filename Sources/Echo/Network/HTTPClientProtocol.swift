// HTTPClientProtocol.swift
// Echo - Network
// Protocol for HTTP client to enable dependency injection and VCR playback

import Foundation
import NIOCore
import NIOHTTP1

/// Protocol for HTTP client implementations
/// Enables dependency injection for testing with VCR cassettes
public protocol HTTPClientProtocol: Sendable {
    /// Performs a generic HTTP request with body
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - method: HTTP method (defaults to POST)
    ///   - body: Request body (Encodable)
    ///   - estimatedTokens: Estimated tokens for rate limiting
    /// - Returns: Decoded response
    /// - Throws: HTTPError if request fails
    func request<T: Decodable & Sendable, B: Encodable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: B,
        estimatedTokens: Int
    ) async throws -> T

    /// Streams a response using Server-Sent Events (SSE)
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - body: Request body (Encodable)
    ///   - estimatedTokens: Estimated tokens for rate limiting
    /// - Returns: AsyncThrowingStream of ByteBuffer chunks
    func stream<B: Encodable & Sendable>(
        endpoint: String,
        body: B,
        estimatedTokens: Int
    ) async -> AsyncThrowingStream<ByteBuffer, Error>

    /// Performs a GET request
    /// - Parameter endpoint: API endpoint path
    /// - Returns: Decoded response
    /// - Throws: HTTPError if request fails
    func get<T: Decodable & Sendable>(endpoint: String) async throws -> T

    /// Performs a DELETE request
    /// - Parameter endpoint: API endpoint path
    /// - Throws: HTTPError if request fails
    func delete(endpoint: String) async throws

    /// Performs a POST request without body
    /// - Parameter endpoint: API endpoint path
    /// - Returns: Decoded response
    /// - Throws: HTTPError if request fails
    func post<T: Decodable & Sendable>(endpoint: String) async throws -> T
}
