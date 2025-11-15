// RealtimeError.swift
// Echo - Realtime API
// Error types specific to the Realtime API

import Foundation

/// Errors that can occur when using the Realtime API
public enum RealtimeError: Error, LocalizedError {
    // MARK: - Model Errors

    /// The specified model is not supported by the Realtime API.
    /// Only gpt-realtime and gpt-realtime-mini are valid.
    case unsupportedModel(String)

    // MARK: - Connection Errors

    /// Failed to connect to the Realtime API WebSocket
    case connectionFailed(Error)

    /// Connection was closed unexpectedly
    case connectionClosed

    /// Not currently connected to the Realtime API
    case notConnected

    /// Already connected to the Realtime API
    case alreadyConnected

    // MARK: - Session Errors

    /// Failed to initialize the session
    case sessionInitializationFailed(String)

    /// Session configuration is invalid
    case invalidSessionConfiguration(String)

    // MARK: - Audio Errors

    /// Failed to start audio capture
    case audioCaptureFailed(Error)

    /// Failed to start audio playback
    case audioPlaybackFailed(Error)

    /// Audio format is not supported
    case unsupportedAudioFormat(String)

    /// Audio buffer error
    case audioBufferError(String)

    // MARK: - Protocol Errors

    /// Failed to encode a client event
    case eventEncodingFailed(Error)

    /// Failed to decode a server event
    case eventDecodingFailed(Error)

    /// Received an unexpected event type
    case unexpectedEvent(String)

    /// Server returned an error
    case serverError(code: String, message: String)

    // MARK: - Conversation Errors

    /// Invalid conversation item
    case invalidConversationItem(String)

    /// Conversation item not found
    case conversationItemNotFound(String)

    // MARK: - Response Errors

    /// Failed to create response
    case responseCreationFailed(String)

    /// Response was cancelled
    case responseCancelled

    // MARK: - General Errors

    /// Operation timed out
    case timeout

    /// Invalid API key
    case invalidAPIKey

    /// Rate limit exceeded
    case rateLimitExceeded

    /// Unknown error
    case unknown(Error)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        // Model Errors
        case .unsupportedModel(let model):
            return "Model '\(model)' is not supported. Valid Realtime models: gpt-realtime, gpt-realtime-mini"

        // Connection Errors
        case .connectionFailed(let error):
            return "Failed to connect to Realtime API: \(error.localizedDescription)"
        case .connectionClosed:
            return "Connection to Realtime API was closed"
        case .notConnected:
            return "Not connected to Realtime API"
        case .alreadyConnected:
            return "Already connected to Realtime API"

        // Session Errors
        case .sessionInitializationFailed(let reason):
            return "Failed to initialize session: \(reason)"
        case .invalidSessionConfiguration(let reason):
            return "Invalid session configuration: \(reason)"

        // Audio Errors
        case .audioCaptureFailed(let error):
            return "Failed to start audio capture: \(error.localizedDescription)"
        case .audioPlaybackFailed(let error):
            return "Failed to start audio playback: \(error.localizedDescription)"
        case .unsupportedAudioFormat(let format):
            return "Unsupported audio format: \(format)"
        case .audioBufferError(let reason):
            return "Audio buffer error: \(reason)"

        // Protocol Errors
        case .eventEncodingFailed(let error):
            return "Failed to encode event: \(error.localizedDescription)"
        case .eventDecodingFailed(let error):
            return "Failed to decode event: \(error.localizedDescription)"
        case .unexpectedEvent(let eventType):
            return "Received unexpected event: \(eventType)"
        case .serverError(let code, let message):
            return "Server error [\(code)]: \(message)"

        // Conversation Errors
        case .invalidConversationItem(let reason):
            return "Invalid conversation item: \(reason)"
        case .conversationItemNotFound(let itemId):
            return "Conversation item not found: \(itemId)"

        // Response Errors
        case .responseCreationFailed(let reason):
            return "Failed to create response: \(reason)"
        case .responseCancelled:
            return "Response was cancelled"

        // General Errors
        case .timeout:
            return "Operation timed out"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }

    public var failureReason: String? {
        return errorDescription
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupportedModel:
            return "Use either 'gpt-realtime' or 'gpt-realtime-mini' as the model."
        case .notConnected:
            return "Call connect() before attempting to send messages."
        case .alreadyConnected:
            return "Disconnect first before reconnecting."
        case .invalidAPIKey:
            return "Check that your OpenAI API key is valid and has access to the Realtime API."
        case .rateLimitExceeded:
            return "Wait before making more requests or check your API limits."
        case .audioCaptureFailed, .audioPlaybackFailed:
            return "Check microphone and audio permissions."
        default:
            return nil
        }
    }
}
