// ResponsesClient.swift
// Echo - Responses API
// Main HTTP/SSE client for the Responses API with model validation

@preconcurrency import Foundation
import NIOCore

/// Main client for interacting with OpenAI's Responses API.
/// Handles both streaming (SSE) and non-streaming requests with full model validation.
public actor ResponsesClient {
    // MARK: - Properties

    /// HTTP client for making requests (protocol to enable DI)
    internal let httpClient: any HTTPClientProtocol

    /// Event emitter for publishing events
    private let eventEmitter: EventEmitter

    /// SSE parser for streaming responses
    private let sseParser: SSEParser

    /// Current session information
    private var session: ResponsesSession?

    /// Enable logging
    private let enableLogging: Bool

    // MARK: - Initialization

    /// Creates a new Responses API client
    /// - Parameters:
    ///   - apiKey: OpenAI API key (provide this OR httpClient)
    ///   - httpClient: HTTP client instance (for dependency injection/testing)
    ///   - eventEmitter: Event emitter for publishing events
    ///   - enableLogging: Whether to enable logging (default: false)
    public init(
        apiKey: String? = nil,
        httpClient: (any HTTPClientProtocol)? = nil,
        eventEmitter: EventEmitter,
        enableLogging: Bool = false
    ) {
        // Use provided httpClient or create default with apiKey
        if let client = httpClient {
            self.httpClient = client
        } else if let key = apiKey {
            self.httpClient = HTTPClient(apiKey: key)
        } else {
            fatalError("ResponsesClient requires either apiKey or httpClient")
        }

        self.eventEmitter = eventEmitter
        self.sseParser = SSEParser()
        self.enableLogging = enableLogging
    }

    // MARK: - Non-Streaming Requests

    /// Creates a response (non-streaming)
    /// - Parameters:
    ///   - model: The model to use (MUST be gpt-5, gpt-5-mini, or gpt-5-nano)
    ///   - input: Input messages
    ///   - instructions: System instructions (optional)
    ///   - tools: Available tools for function calling (optional)
    ///   - temperature: Sampling temperature (default: 0.8)
    ///   - maxOutputTokens: Maximum tokens to generate (optional)
    /// - Returns: The complete response
    /// - Throws: ResponsesError if the request fails or model is unsupported
    public func createResponse(
        model: ResponsesModel,
        input: [Message],
        instructions: String? = nil,
        tools: [ResponsesTool] = [],
        temperature: Double = 0.8,
        maxOutputTokens: Int? = nil
    ) async throws -> ResponsesResponse {
        // CRITICAL: Validate model
        try validateModel(model)

        log("Creating response with model: \(model.rawValue)")

        // Convert messages to API format
        let apiMessages = input.map { message in
            InputMessage(role: message.role.rawValue, content: message.text)
        }

        // Build request with proper temperature
        // Only include temperature if the model supports it
        let request = ResponsesRequest(
            model: model.rawValue,
            input: .messages(apiMessages),
            instructions: instructions,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : "auto",  // Let model decide when to use tools
            temperature: model.supportsTemperature ? temperature : nil,
            maxOutputTokens: maxOutputTokens,
            stream: false
        )

        // Estimate tokens for rate limiting
        let estimatedTokens = estimateTokens(for: input) + (maxOutputTokens ?? 1000)

        // Execute request
        do {
            let response: ResponsesResponse = try await httpClient.request(
                endpoint: "/responses",
                method: .POST,
                body: request,
                estimatedTokens: estimatedTokens
            )

            log("Response created: \(response.id)")

            // Emit connection status
            await eventEmitter.emit(.connectionStatusChanged(isConnected: true))

            // Don't emit messageFinalized here - MessageQueue handles it
            // This prevents duplicate messages in the UI

            return response

        } catch let error as HTTPError {
            await eventEmitter.emit(.connectionStatusChanged(isConnected: false))
            throw convertHTTPError(error)
        } catch {
            await eventEmitter.emit(.error(error: error))
            throw ResponsesError.networkError(error)
        }
    }

    // MARK: - Streaming Requests

    /// Processes a streaming response with a handler to avoid Sendable issues
    /// - Parameters:
    ///   - model: The model to use
    ///   - input: Input messages
    ///   - instructions: System instructions (optional)
    ///   - tools: Available tools for function calling (optional)
    ///   - temperature: Sampling temperature (default: 0.8)
    ///   - maxOutputTokens: Maximum tokens to generate (optional)
    ///   - handler: Closure that processes the stream (isolated to this actor)
    public func withStreamResponse(
        model: ResponsesModel,
        input: [Message],
        instructions: String? = nil,
        tools: [ResponsesTool] = [],
        temperature: Double = 0.8,
        maxOutputTokens: Int? = nil,
        reasoningEffort: ReasoningEffort = .none,
        handler: @Sendable (AsyncThrowingStream<StreamEvent, Error>) async throws -> Void
    ) async rethrows {
        let stream = streamResponse(
            model: model,
            input: input,
            instructions: instructions,
            tools: tools,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            reasoningEffort: reasoningEffort
        )
        try await handler(stream)
    }

    /// Creates a streaming response (SSE)
    /// - Parameters:
    ///   - model: The model to use (MUST be gpt-5, gpt-5-mini, or gpt-5-nano)
    ///   - input: Input messages
    ///   - instructions: System instructions (optional)
    ///   - tools: Available tools for function calling (optional)
    ///   - temperature: Sampling temperature (default: 0.8)
    ///   - maxOutputTokens: Maximum tokens to generate (optional)
    /// - Returns: AsyncThrowingStream of StreamEvent
    /// - Throws: ResponsesError if model is unsupported
    @preconcurrency
    public func streamResponse(
        model: ResponsesModel,
        input: [Message],
        instructions: String? = nil,
        tools: [ResponsesTool] = [],
        temperature: Double = 0.8,
        maxOutputTokens: Int? = nil,
        reasoningEffort: ReasoningEffort = .none
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // CRITICAL: Validate model
                    try validateModel(model)

                    log("Streaming response with model: \(model.rawValue)")

                    // Reset SSE parser
                    await sseParser.reset()

                    // Convert messages to API format
                    let apiMessages: [InputMessage] = input.map { message in
                        InputMessage(role: message.role.rawValue, content: message.text)
                    }

                    // Build request with proper temperature
                    // Only include temperature if the model supports it
                    let request = ResponsesRequest(
                        model: model.rawValue,
                        input: .messages(apiMessages),
                        instructions: instructions,
                        tools: tools.isEmpty ? nil : tools,
                        toolChoice: tools.isEmpty ? nil : "auto",  // Let model decide when to use tools
                        temperature: model.supportsTemperature ? temperature : nil,
                        maxOutputTokens: maxOutputTokens,
                        stream: true,
                        reasoningEffort: reasoningEffort == .none ? nil : reasoningEffort.rawValue
                    )

                    // Estimate tokens for rate limiting
                    let estimatedTokens = estimateTokens(for: input) + (maxOutputTokens ?? 1000)

                    // Emit connection status
                    await eventEmitter.emit(.connectionStatusChanged(isConnected: true))

                    // Stream response
                    let stream = await httpClient.stream(
                        endpoint: "/responses",
                        body: request,
                        estimatedTokens: estimatedTokens
                    )

                    var accumulatedText = ""

                    for try await chunk in stream {
                        // Convert ByteBuffer to String
                        let chunkString = String(buffer: chunk)

                        // Parse SSE events
                        let eventStrings = await sseParser.parse(chunk: chunkString)

                        for eventData in eventStrings {
                            guard let data = eventData.data(using: .utf8) else { continue }

                            do {
                                // First try to decode the raw JSON to see what we're dealing with
                                if enableLogging {
                                    if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        log("RAW SSE JSON: \(jsonDict)")
                                    }
                                }
                                
                                let event = try JSONDecoder().decode(StreamEvent.self, from: data)

                                // Log event if logging enabled
                                if enableLogging {
                                    log("Parsed event: \(event)")
                                }

                                // Emit specific events based on type
                                switch event {
                                case .responseDelta(let delta):
                                    log("Text delta: \"\(delta)\"")
                                    accumulatedText += delta
                                    await eventEmitter.emit(.assistantTextDelta(delta: delta))

                                case .toolCallDelta(_, let name, _):
                                    log("Tool call delta: \(name)")

                                case .toolCallDone(let id, let name, let argumentsString):
                                    // Parse arguments string to SendableJSON
                                    let argumentsData = argumentsString.data(using: .utf8) ?? Data()
                                    let arguments = (try? SendableJSON.from(data: argumentsData)) ?? .null
                                    let toolCall = ToolCall(id: id, name: name, arguments: arguments)
                                    await eventEmitter.emit(.toolCallRequested(toolCall: toolCall))
                                    log("Tool call: \(name)")

                                case .responseDone(let response):
                                    // Don't emit messageFinalized here - MessageQueue handles it
                                    // This prevents duplicate messages in the UI
                                    log("Response completed: \(response.id)")

                                case .raw(let type, _):
                                    // Silently ignore raw events (they're informational only)
                                    log("Ignored event: \(type)")

                                default:
                                    break
                                }

                                continuation.yield(event)

                            } catch {
                                // Only log decoding errors if logging is enabled
                                if enableLogging {
                                    log("Failed to decode SSE event: \(error)")
                                    if let jsonString = String(data: data, encoding: .utf8) {
                                        log("Failed JSON: \(jsonString)")
                                    }
                                }
                            }
                        }
                    }

                    continuation.finish()
                    // NOTE: Don't emit disconnected here - Responses API is stateless
                    // and ready for next request immediately

                } catch {
                    await eventEmitter.emit(.connectionStatusChanged(isConnected: false))
                    await eventEmitter.emit(.error(error: error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Model Validation

    /// Validates that the model is supported by the Responses API
    /// - Parameter model: The model to validate
    /// - Throws: ResponsesError.unsupportedModel if the model is not supported
    private func validateModel(_ model: ResponsesModel) throws {
        // The ResponsesModel enum already restricts to valid models,
        // but we validate the raw value as an extra safety check
        let validModels: Set<String> = ["gpt-5", "gpt-5-mini", "gpt-5-nano"]

        guard validModels.contains(model.rawValue) else {
            throw ResponsesError.unsupportedModel(
                "Model '\(model.rawValue)' is not supported. " +
                "Valid Responses models: gpt-5, gpt-5-mini, gpt-5-nano"
            )
        }

        log("Model validation passed: \(model.rawValue)")
    }

    // MARK: - Helper Methods

    /// Estimates token count for messages (rough estimate)
    private func estimateTokens(for messages: [Message]) -> Int {
        let totalChars = messages.reduce(0) { $0 + $1.text.count }
        // Rough estimate: ~4 chars per token
        return max(totalChars / 4, 100)
    }

    /// Converts HTTP error to ResponsesError
    private func convertHTTPError(_ error: HTTPError) -> ResponsesError {
        switch error {
        case .httpStatus(let code):
            switch code {
            case 401:
                return .authenticationFailed
            case 429:
                return .rateLimitExceeded(retryAfter: nil)
            case 400:
                return .invalidRequest("Bad request")
            default:
                return .httpError(code)
            }
        case .timeout:
            return .timeout
        case .invalidResponse:
            return .invalidResponse("Invalid HTTP response")
        }
    }

    /// Creates a response with response format (for structured outputs)
    /// - Parameters:
    ///   - model: The model to use
    ///   - input: Input messages
    ///   - instructions: System instructions (optional)
    ///   - tools: Available tools for function calling (optional)
    ///   - temperature: Sampling temperature
    ///   - maxOutputTokens: Maximum tokens to generate (optional)
    ///   - responseFormat: Response format for structured output
    /// - Returns: The complete response
    /// - Throws: ResponsesError if the request fails
    public func createResponseWithFormat(
        model: ResponsesModel,
        input: [Message],
        instructions: String? = nil,
        tools: [ResponsesTool] = [],
        temperature: Double = 0.8,
        maxOutputTokens: Int? = nil,
        responseFormat: ResponseFormat
    ) async throws -> ResponsesResponse {
        // CRITICAL: Validate model
        try validateModel(model)
        
        log("Creating response with format: \(responseFormat.type)")
        
        // Convert messages to API format
        let apiMessages = input.map { message in
            InputMessage(role: message.role.rawValue, content: message.text)
        }
        
        // Build request with response format
        let request = ResponsesRequest(
            model: model.rawValue,
            input: .messages(apiMessages),
            instructions: instructions,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : "auto",
            responseFormat: responseFormat,
            temperature: model.supportsTemperature ? temperature : nil,
            maxOutputTokens: maxOutputTokens,
            stream: false  // Structured outputs don't support streaming
        )
        
        // Estimate tokens
        let estimatedTokens = estimateTokens(for: input) + (maxOutputTokens ?? 1000)
        
        // Execute request
        do {
            let response: ResponsesResponse = try await httpClient.request(
                endpoint: "/responses",
                method: .POST,
                body: request,
                estimatedTokens: estimatedTokens
            )
            
            log("Response created with format: \(response.id)")
            
            // Emit connection status
            await eventEmitter.emit(.connectionStatusChanged(isConnected: true))
            
            return response
            
        } catch let error as HTTPError {
            await eventEmitter.emit(.connectionStatusChanged(isConnected: false))
            throw convertHTTPError(error)
        } catch {
            await eventEmitter.emit(.error(error: error))
            throw ResponsesError.networkError(error)
        }
    }
    
    // MARK: - Response Management (CRUD Operations)

    /// Retrieves a specific response by ID
    /// - Parameter id: The response ID to retrieve
    /// - Returns: The response object
    /// - Throws: ResponsesError if the request fails
    public func getResponse(id: String) async throws -> ResponsesResponse {
        log("Getting response: \(id)")

        do {
            let response: ResponsesResponse = try await httpClient.get(
                endpoint: "/responses/\(id)"
            )

            log("Retrieved response: \(response.id)")
            return response
        } catch {
            await eventEmitter.emit(.error(error: error))
            throw ResponsesError.networkError(error)
        }
    }

    /// Deletes a response
    /// - Parameter id: The response ID to delete
    /// - Throws: ResponsesError if the request fails
    public func deleteResponse(id: String) async throws {
        log("Deleting response: \(id)")

        do {
            try await httpClient.delete(endpoint: "/responses/\(id)")
            log("Deleted response: \(id)")
        } catch {
            await eventEmitter.emit(.error(error: error))
            throw ResponsesError.networkError(error)
        }
    }

    /// Cancels an in-progress response
    /// - Parameter id: The response ID to cancel
    /// - Throws: ResponsesError if the request fails
    public func cancelResponse(id: String) async throws {
        log("Cancelling response: \(id)")

        do {
            let _: ResponsesResponse = try await httpClient.post(
                endpoint: "/responses/\(id)/cancel"
            )
            log("Cancelled response: \(id)")
        } catch {
            await eventEmitter.emit(.error(error: error))
            throw ResponsesError.networkError(error)
        }
    }

    /// Lists responses with optional pagination
    /// - Parameters:
    ///   - limit: Maximum number of responses to return (default: 20)
    ///   - after: Cursor for pagination (optional)
    /// - Returns: Array of responses
    /// - Throws: ResponsesError if the request fails
    public func listResponses(limit: Int? = 20, after: String? = nil) async throws -> [ResponsesResponse] {
        log("Listing responses (limit: \(limit ?? 20))")

        var endpoint = "/responses?limit=\(limit ?? 20)"
        if let after = after {
            endpoint += "&after=\(after)"
        }

        do {
            struct ResponsesList: Codable {
                let data: [ResponsesResponse]
            }

            let list: ResponsesList = try await httpClient.get(endpoint: endpoint)
            log("Retrieved \(list.data.count) responses")
            return list.data
        } catch {
            await eventEmitter.emit(.error(error: error))
            throw ResponsesError.networkError(error)
        }
    }

    /// Logs a message if logging is enabled
    private func log(_ message: String) {
        if enableLogging {
            print("[ResponsesClient] \(message)")
        }
    }
}
