// ResponseInfo.swift
// Echo - Realtime API
// Response information from server events

import Foundation

/// Response information from the Realtime API
public struct ResponseInfo: Sendable {
    /// Response ID
    public let id: String
    
    /// Response status (e.g., "completed", "cancelled")
    public let status: String?
    
    /// Usage information for this response (available when status is "completed")
    public let usage: RealtimeUsage?

    static func parse(from data: [String: Any]) throws -> ResponseInfo {
        var usage: RealtimeUsage? = nil
        
        // Parse usage if present
        if let usageData = data["usage"] as? [String: Any] {
            usage = RealtimeUsage.parse(from: usageData)
        }
        
        return ResponseInfo(
            id: data["id"] as? String ?? "",
            status: data["status"] as? String,
            usage: usage
        )
    }
}

/// Usage information from the Realtime API response
public struct RealtimeUsage: Sendable, Codable {
    /// Total tokens used (input + output)
    public let totalTokens: Int
    
    /// Input tokens (prompt)
    public let inputTokens: Int
    
    /// Output tokens (completion)
    public let outputTokens: Int
    
    /// Detailed breakdown of input tokens
    public let inputTokenDetails: TokenDetails?
    
    /// Detailed breakdown of output tokens
    public let outputTokenDetails: TokenDetails?
    
    /// Creates a RealtimeUsage instance
    public init(
        totalTokens: Int,
        inputTokens: Int,
        outputTokens: Int,
        inputTokenDetails: TokenDetails? = nil,
        outputTokenDetails: TokenDetails? = nil
    ) {
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.inputTokenDetails = inputTokenDetails
        self.outputTokenDetails = outputTokenDetails
    }
    
    /// Parses usage from API response
    static func parse(from data: [String: Any]) -> RealtimeUsage {
        let totalTokens = data["total_tokens"] as? Int ?? 0
        let inputTokens = data["input_tokens"] as? Int ?? 0
        let outputTokens = data["output_tokens"] as? Int ?? 0
        
        var inputDetails: TokenDetails? = nil
        var outputDetails: TokenDetails? = nil
        
        if let inputData = data["input_token_details"] as? [String: Any] {
            inputDetails = TokenDetails.parse(from: inputData)
        }
        
        if let outputData = data["output_token_details"] as? [String: Any] {
            outputDetails = TokenDetails.parse(from: outputData)
        }
        
        return RealtimeUsage(
            totalTokens: totalTokens,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            inputTokenDetails: inputDetails,
            outputTokenDetails: outputDetails
        )
    }
    
    // MARK: - Convenience Properties
    
    /// Audio input tokens (from input_token_details)
    public var audioInputTokens: Int {
        inputTokenDetails?.audioTokens ?? 0
    }
    
    /// Audio output tokens (from output_token_details)
    public var audioOutputTokens: Int {
        outputTokenDetails?.audioTokens ?? 0
    }
    
    /// Text input tokens (from input_token_details)
    public var textInputTokens: Int {
        inputTokenDetails?.textTokens ?? 0
    }
    
    /// Text output tokens (from output_token_details)
    public var textOutputTokens: Int {
        outputTokenDetails?.textTokens ?? 0
    }
    
    /// Cached tokens that were reused (from input_token_details)
    public var cachedTokens: Int {
        inputTokenDetails?.cachedTokens ?? 0
    }
    
    /// Total audio tokens (input + output)
    public var totalAudioTokens: Int {
        audioInputTokens + audioOutputTokens
    }
}

/// Detailed token breakdown
public struct TokenDetails: Sendable, Codable {
    /// Cached tokens that were reused
    public let cachedTokens: Int
    
    /// Text tokens
    public let textTokens: Int
    
    /// Audio tokens
    public let audioTokens: Int
    
    /// Creates a TokenDetails instance
    public init(cachedTokens: Int = 0, textTokens: Int = 0, audioTokens: Int = 0) {
        self.cachedTokens = cachedTokens
        self.textTokens = textTokens
        self.audioTokens = audioTokens
    }
    
    /// Parses token details from API response
    static func parse(from data: [String: Any]) -> TokenDetails {
        TokenDetails(
            cachedTokens: data["cached_tokens"] as? Int ?? 0,
            textTokens: data["text_tokens"] as? Int ?? 0,
            audioTokens: data["audio_tokens"] as? Int ?? 0
        )
    }
}
