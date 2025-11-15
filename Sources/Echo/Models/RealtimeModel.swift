import Foundation

/// Available models for the Realtime API.
///
/// These models support real-time audio input and output via WebSocket connection.
/// All Realtime models support speech-to-speech conversation with automatic
/// transcription, voice activity detection, and function calling.
public enum RealtimeModel: String, Sendable, Codable, CaseIterable {
    /// GPT Realtime - The standard real-time audio model.
    /// The recommended model for real-time audio conversations.
    case gptRealtime = "gpt-realtime"

    /// GPT Realtime Mini - Smaller, faster variant.
    /// Optimized for lower-latency applications.
    case gptRealtimeMini = "gpt-realtime-mini"

    // MARK: - Properties

    /// User-friendly name for the model.
    public var name: String {
        switch self {
        case .gptRealtime:
            return "GPT Realtime"
        case .gptRealtimeMini:
            return "GPT Realtime Mini"
        }
    }

    /// Brief description of the model.
    public var modelDescription: String {
        switch self {
        case .gptRealtime:
            return "Standard model optimized for real-time audio conversations with high quality and low latency."
        case .gptRealtimeMini:
            return "Faster, more cost-effective variant for applications requiring lower latency."
        }
    }

    /// Whether this is the recommended default model.
    public var isDefault: Bool {
        return self == .gptRealtime
    }

    /// Expected latency characteristics.
    public var latency: LatencyProfile {
        switch self {
        case .gptRealtime:
            return .standard
        case .gptRealtimeMini:
            return .low
        }
    }

    /// Audio formats supported by this model.
    public var supportedAudioFormats: [String] {
        return ["pcm16", "g711_ulaw", "g711_alaw"]
    }

    /// Maximum audio duration in seconds (for input buffer).
    public var maxAudioDuration: TimeInterval {
        return 300 // 5 minutes
    }

    /// Capabilities for this model.
    public var capabilities: ModelCapabilities {
        ModelCapabilities(
            supportsAudio: true,
            supportsStreaming: true,
            supportsTools: true,
            supportsStructuredOutputs: false,
            supportsVision: false,
            maxContextTokens: contextWindow,
            maxOutputTokens: maxOutputTokens
        )
    }

    // MARK: - Token Limits

    /// Context window size in tokens.
    public var contextWindow: Int {
        return 128_000
    }

    /// Maximum output tokens per response.
    /// CRITICAL: These values MUST match the UAD specification exactly.
    public var maxOutputTokens: Int {
        switch self {
        case .gptRealtime:
            return 4_096  // UAD requirement
        case .gptRealtimeMini:
            return 2_048  // UAD requirement
        }
    }

    // MARK: - Latency Profile

    /// Expected latency characteristics for a model.
    public enum LatencyProfile: String, Sendable {
        /// Standard latency (typically 200-500ms).
        case standard

        /// Low latency (typically 100-300ms).
        case low

        /// Very low latency (typically 50-200ms).
        case veryLow
    }
}

// MARK: - CustomStringConvertible

extension RealtimeModel: CustomStringConvertible {
    public var description: String {
        return name
    }
}

// MARK: - Convenience Accessors

extension RealtimeModel {
    /// The default recommended Realtime model.
    public static var `default`: RealtimeModel {
        return .gptRealtime
    }

    /// The fastest available Realtime model.
    public static var fastest: RealtimeModel {
        return .gptRealtimeMini
    }

    /// The most capable Realtime model.
    public static var mostCapable: RealtimeModel {
        return .gptRealtime
    }
}
