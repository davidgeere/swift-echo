import Foundation

/// Echo errors
public enum EchoError: Error, LocalizedError {
    case unsupportedModel(String)
    case configurationError(String)
    case clientNotInitialized(String)
    case invalidMode(String)
    case connectionFailed(String)
    case invalidConfiguration(String)
    
    // Embeddings API errors
    case embeddingError(String)
    
    // Network and API errors
    case authenticationFailed
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case invalidRequest(String)
    case httpError(Int)
    case timeout
    case invalidResponse(String)
    case networkError(Error)
    
    // Structured output errors
    case structuredOutputFailed(String)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .unsupportedModel(let message):
            return "Unsupported model: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .clientNotInitialized(let message):
            return "Client not initialized: \(message)"
        case .invalidMode(let message):
            return "Invalid mode: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
            
        // Embeddings API errors
        case .embeddingError(let message):
            return "Embedding error: \(message)"
            
        // Network and API errors
        case .authenticationFailed:
            return "Authentication failed: Invalid API key"
        case .rateLimitExceeded(let retryAfter):
            if let retry = retryAfter {
                return "Rate limit exceeded. Retry after \(retry) seconds"
            }
            return "Rate limit exceeded"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .timeout:
            return "Request timed out"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
            
        // Structured output errors
        case .structuredOutputFailed(let message):
            return "Structured output failed: \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
