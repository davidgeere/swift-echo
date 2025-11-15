// ResponsesError.swift
// Echo - Responses API
// Error types for Responses API operations

import Foundation

/// Errors that can occur during Responses API operations
public enum ResponsesError: Error, CustomStringConvertible, Sendable {
    // MARK: - Model Errors

    /// Model is not supported by the Responses API
    case unsupportedModel(String)

    // MARK: - Request Errors

    /// Invalid request parameters
    case invalidRequest(String)

    /// Missing required parameter
    case missingParameter(String)

    /// Invalid JSON in request body
    case invalidJSON(String)

    // MARK: - Network Errors

    /// HTTP error with status code
    case httpError(UInt)

    /// Network connection failed
    case networkError(Error)

    /// Request timeout
    case timeout

    // MARK: - Response Errors

    /// Invalid or malformed response
    case invalidResponse(String)

    /// Failed to decode response
    case decodingError(Error)

    /// SSE parsing error
    case sseParsingError(String)

    // MARK: - API Errors

    /// Authentication failed (invalid API key)
    case authenticationFailed

    /// Rate limit exceeded
    case rateLimitExceeded(retryAfter: Int?)

    /// Insufficient quota/credits
    case insufficientQuota

    /// API returned an error
    case apiError(code: String, message: String)

    // MARK: - Content Errors

    /// Content was filtered by moderation
    case contentFiltered(String)

    /// Context length exceeded
    case contextLengthExceeded(maxTokens: Int)

    // MARK: - Tool Errors

    /// Tool execution failed
    case toolExecutionFailed(toolName: String, error: String)

    /// Invalid tool definition
    case invalidToolDefinition(String)

    // MARK: - Structured Output Errors

    /// Failed to generate structured output
    case structuredOutputFailed(String)

    /// Invalid JSON schema
    case invalidJSONSchema(String)

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .unsupportedModel(let message):
            return "Unsupported model: \(message)"

        case .invalidRequest(let message):
            return "Invalid request: \(message)"

        case .missingParameter(let param):
            return "Missing required parameter: \(param)"

        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"

        case .httpError(let code):
            return "HTTP error \(code): \(httpErrorDescription(code))"

        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"

        case .timeout:
            return "Request timeout"

        case .invalidResponse(let message):
            return "Invalid response: \(message)"

        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"

        case .sseParsingError(let message):
            return "SSE parsing error: \(message)"

        case .authenticationFailed:
            return "Authentication failed - check your API key"

        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limit exceeded - retry after \(seconds) seconds"
            }
            return "Rate limit exceeded"

        case .insufficientQuota:
            return "Insufficient quota - check your API usage and billing"

        case .apiError(let code, let message):
            return "API error [\(code)]: \(message)"

        case .contentFiltered(let reason):
            return "Content filtered: \(reason)"

        case .contextLengthExceeded(let maxTokens):
            return "Context length exceeded (max: \(maxTokens) tokens)"

        case .toolExecutionFailed(let toolName, let error):
            return "Tool '\(toolName)' execution failed: \(error)"

        case .invalidToolDefinition(let message):
            return "Invalid tool definition: \(message)"

        case .structuredOutputFailed(let message):
            return "Structured output generation failed: \(message)"

        case .invalidJSONSchema(let message):
            return "Invalid JSON schema: \(message)"
        }
    }

    // MARK: - Helpers

    /// Returns a user-friendly description for HTTP error codes
    private func httpErrorDescription(_ code: UInt) -> String {
        switch code {
        case 400:
            return "Bad Request"
        case 401:
            return "Unauthorized - invalid API key"
        case 403:
            return "Forbidden"
        case 404:
            return "Not Found"
        case 429:
            return "Too Many Requests - rate limit exceeded"
        case 500:
            return "Internal Server Error"
        case 502:
            return "Bad Gateway"
        case 503:
            return "Service Unavailable"
        case 504:
            return "Gateway Timeout"
        default:
            return "Unknown Error"
        }
    }

    /// Whether this error is retryable
    public var isRetryable: Bool {
        switch self {
        case .httpError(let code):
            return code == 429 || code >= 500
        case .networkError, .timeout:
            return true
        case .rateLimitExceeded:
            return true
        default:
            return false
        }
    }
}
