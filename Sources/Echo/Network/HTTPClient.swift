// HTTPClient.swift
// Echo - Network Infrastructure
// HTTP client for Responses API using async-http-client

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

// MARK: - Helper Types

/// Empty request body for GET/DELETE/POST requests without payload
private struct EmptyRequestBody: Encodable {}

/// Empty response body for DELETE requests
private struct EmptyResponseBody: Decodable {}

// MARK: - HTTPClient

/// HTTP client for making requests to the OpenAI Responses API.
/// Wraps AsyncHTTPClient for thread-safe, actor-based access.
/// Conforms to HTTPClientProtocol to enable dependency injection.
public actor HTTPClient: HTTPClientProtocol {
    // MARK: - Properties

    /// The underlying AsyncHTTPClient instance
    private let client: AsyncHTTPClient.HTTPClient

    /// Base URL for OpenAI API
    private let baseURL: String

    /// API key for authentication
    private let apiKey: String

    /// Rate limiter for request throttling
    private let rateLimiter: RateLimiter

    /// Retry policy for failed requests
    private let retryPolicy: RetryPolicy

    // MARK: - Initialization

    /// Creates a new HTTP client
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - baseURL: Base URL for API (defaults to OpenAI production)
    ///   - rateLimiter: Rate limiter instance (defaults to standard limits)
    ///   - retryPolicy: Retry policy (defaults to standard retry)
    public init(
        apiKey: String,
        baseURL: String = "https://api.openai.com/v1",
        rateLimiter: RateLimiter = RateLimiter(),
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.rateLimiter = rateLimiter
        self.retryPolicy = retryPolicy

        // Configure AsyncHTTPClient with reasonable defaults
        var configuration = AsyncHTTPClient.HTTPClient.Configuration()
        configuration.timeout = .init(
            connect: .seconds(10),
            read: .seconds(300)  // Long timeout for streaming
        )

        self.client = AsyncHTTPClient.HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: configuration
        )
    }

    deinit {
        // Shutdown the client when deallocated
        try? client.syncShutdown()
    }

    // MARK: - Request Methods

    /// Executes a JSON request and returns decoded response
    /// - Parameters:
    ///   - endpoint: API endpoint path (e.g., "/responses")
    ///   - method: HTTP method
    ///   - body: Request body (will be JSON encoded)
    ///   - estimatedTokens: Estimated tokens for rate limiting
    /// - Returns: Decoded response
    public func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        endpoint: String,
        method: HTTPMethod,
        body: Request,
        estimatedTokens: Int
    ) async throws -> Response {
        // Wait for rate limit capacity
        try await rateLimiter.waitForCapacity(estimatedTokens: estimatedTokens)

        // Attempt request with retry logic
        var attempt = 0
        while true {
            do {
                // Build request
                var request = HTTPClientRequest(url: "\(baseURL)\(endpoint)")
                request.method = method
                request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")

                // Only add body for methods that support it (not GET, DELETE, HEAD)
                if method != .GET && method != .DELETE && method != .HEAD {
                    request.headers.add(name: "Content-Type", value: "application/json")

                    // Encode body
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let bodyData = try encoder.encode(body)

                    // DEBUG: Print request body
                    if let bodyString = String(data: bodyData, encoding: .utf8) {
                        print("📤 [HTTPClient] Request to \(endpoint):")
                        print(bodyString)
                    }

                    request.body = .bytes(ByteBuffer(data: bodyData))
                }

                // Execute request
                let response = try await client.execute(request, timeout: .seconds(60))

                // Update rate limiter from headers
                await updateRateLimiter(from: response.headers)

                // Check status
                guard response.status == .ok else {
                    // Try to read error body for better error messages
                    let errorData = try await response.body.collect(upTo: 1024 * 1024) // 1MB max
                    if let errorString = String(data: Data(buffer: errorData), encoding: .utf8) {
                        print("❌ [HTTPClient] HTTP \(response.status.code) error response:")
                        print(errorString)
                    }
                    throw HTTPError.httpStatus(response.status.code)
                }

                // Decode response
                let responseData = try await response.body.collect(upTo: 10 * 1024 * 1024) // 10MB max
                return try JSONDecoder().decode(Response.self, from: Data(buffer: responseData))

            } catch {
                // Check if we should retry
                guard retryPolicy.shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }

                // Increment attempt and delay
                attempt += 1
                try await retryPolicy.delayForAttempt(attempt)
            }
        }
    }

    /// Executes a streaming request and returns SSE event stream
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - body: Request body (will be JSON encoded)
    ///   - estimatedTokens: Estimated tokens for rate limiting
    /// - Returns: AsyncThrowingStream of raw SSE data chunks
    public func stream<Request: Encodable & Sendable>(
        endpoint: String,
        body: Request,
        estimatedTokens: Int
    ) -> AsyncThrowingStream<ByteBuffer, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Wait for rate limit capacity
                    try await rateLimiter.waitForCapacity(estimatedTokens: estimatedTokens)

                    // Build request
                    var request = HTTPClientRequest(url: "\(baseURL)\(endpoint)")
                    request.method = .POST
                    request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
                    request.headers.add(name: "Content-Type", value: "application/json")
                    request.headers.add(name: "Accept", value: "text/event-stream")

                    // Encode body
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let bodyData = try encoder.encode(body)

                    // DEBUG: Print request body
                    if let bodyString = String(data: bodyData, encoding: .utf8) {
                        print("📤 [HTTPClient] Streaming request to \(endpoint):")
                        print(bodyString)
                    }

                    request.body = .bytes(ByteBuffer(data: bodyData))

                    // Execute request
                    let response = try await client.execute(request, timeout: .seconds(300))

                    // Update rate limiter from headers
                    await updateRateLimiter(from: response.headers)

                    // Check status
                    guard response.status == .ok else {
                        // Try to read error body for better error messages
                        var errorChunks: [ByteBuffer] = []
                        for try await chunk in response.body {
                            errorChunks.append(chunk)
                            if errorChunks.reduce(0, { $0 + $1.readableBytes }) > 1024 * 1024 {
                                break // Max 1MB
                            }
                        }
                        var combinedBuffer = ByteBuffer()
                        for chunk in errorChunks {
                            var chunk = chunk
                            combinedBuffer.writeBuffer(&chunk)
                        }
                        if let errorString = combinedBuffer.getString(at: 0, length: combinedBuffer.readableBytes) {
                            print("❌ [HTTPClient] HTTP \(response.status.code) streaming error response:")
                            print(errorString)
                        }
                        throw HTTPError.httpStatus(response.status.code)
                    }

                    // Stream response body chunks
                    for try await chunk in response.body {
                        continuation.yield(chunk)
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Convenience Methods

    /// Performs a GET request
    /// - Parameter endpoint: API endpoint path
    /// - Returns: Decoded response
    public func get<Response: Decodable & Sendable>(endpoint: String) async throws -> Response {
        return try await request(endpoint: endpoint, method: .GET, body: EmptyRequestBody(), estimatedTokens: 100)
    }

    /// Performs a DELETE request
    /// - Parameter endpoint: API endpoint path
    public func delete(endpoint: String) async throws {
        let _: EmptyResponseBody = try await request(endpoint: endpoint, method: .DELETE, body: EmptyRequestBody(), estimatedTokens: 100)
    }

    /// Performs a POST request without body
    /// - Parameter endpoint: API endpoint path
    /// - Returns: Decoded response
    public func post<Response: Decodable & Sendable>(endpoint: String) async throws -> Response {
        return try await request(endpoint: endpoint, method: .POST, body: EmptyRequestBody(), estimatedTokens: 100)
    }

    // MARK: - Private Helpers

    /// Updates rate limiter based on response headers
    private func updateRateLimiter(from headers: HTTPHeaders) async {
        var headerDict: [String: String] = [:]
        for (name, value) in headers {
            headerDict[name] = value
        }
        await rateLimiter.updateFromHeaders(headerDict)
    }
}

// MARK: - HTTP Error

/// Errors that can occur during HTTP requests
public enum HTTPError: Error, CustomStringConvertible {
    /// HTTP status error
    case httpStatus(UInt)

    /// Request timeout
    case timeout

    /// Invalid response
    case invalidResponse

    public var description: String {
        switch self {
        case .httpStatus(let code):
            return "HTTP error: \(code)"
        case .timeout:
            return "Request timeout"
        case .invalidResponse:
            return "Invalid response"
        }
    }
}
