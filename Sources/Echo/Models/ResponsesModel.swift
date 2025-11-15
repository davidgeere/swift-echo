import Foundation

/// Available models for the Responses API.
///
/// These models support text-based conversations via REST API with optional
/// server-sent events (SSE) streaming. All Responses models support function
/// calling, structured outputs, and long-context conversations.
public enum ResponsesModel: String, Sendable, Codable, CaseIterable {
    // MARK: - GPT-5 Models

    /// GPT-5 - The most capable model for Responses API.
    /// Supports text, vision, and structured outputs.
    case gpt5 = "gpt-5"

    /// GPT-5 Mini - Smaller, faster variant.
    /// More affordable while maintaining strong performance.
    case gpt5Mini = "gpt-5-mini"

    /// GPT-5 Nano - The smallest and fastest variant.
    /// Optimized for speed and cost efficiency.
    case gpt5Nano = "gpt-5-nano"

    // MARK: - Properties

    /// User-friendly name for the model.
    public var name: String {
        switch self {
        case .gpt5:
            return "GPT-5"
        case .gpt5Mini:
            return "GPT-5 Mini"
        case .gpt5Nano:
            return "GPT-5 Nano"
        }
    }

    /// Brief description of the model.
    public var modelDescription: String {
        switch self {
        case .gpt5:
            return "Most capable model with vision, text, and structured outputs."
        case .gpt5Mini:
            return "Faster, more affordable variant for most tasks."
        case .gpt5Nano:
            return "Smallest and fastest variant optimized for speed and cost."
        }
    }

    /// Whether this is the recommended default model.
    public var isDefault: Bool {
        return self == .gpt5
    }

    /// Whether this model supports vision/image inputs.
    public var supportsVision: Bool {
        switch self {
        case .gpt5, .gpt5Mini:
            return true
        case .gpt5Nano:
            return false
        }
    }

    /// Whether this model supports structured outputs.
    public var supportsStructuredOutputs: Bool {
        return true // All GPT-5 models support structured outputs
    }
    
    /// Whether this model supports temperature sampling parameter.
    /// Note: GPT-5 models do not support temperature control.
    public var supportsTemperature: Bool {
        return false // GPT-5 models don't support temperature
    }

    /// Capabilities for this model.
    public var capabilities: ModelCapabilities {
        ModelCapabilities(
            supportsAudio: false,
            supportsStreaming: true,
            supportsTools: true,
            supportsStructuredOutputs: supportsStructuredOutputs,
            supportsVision: supportsVision,
            maxContextTokens: contextWindow,
            maxOutputTokens: maxOutputTokens
        )
    }

    // MARK: - Token Limits

    /// Context window size in tokens.
    public var contextWindow: Int {
        switch self {
        case .gpt5:
            return 200_000
        case .gpt5Mini:
            return 128_000
        case .gpt5Nano:
            return 128_000
        }
    }

    /// Maximum output tokens per response.
    /// CRITICAL: These values MUST match the UAD specification exactly.
    public var maxOutputTokens: Int {
        switch self {
        case .gpt5:
            return 8_192   // UAD requirement (was 32_768)
        case .gpt5Mini:
            return 4_096   // UAD requirement (was 16_384)
        case .gpt5Nano:
            return 2_048   // UAD requirement (was 16_384)
        }
    }

    // MARK: - Cost Tier

    /// Relative cost tier for this model.
    public var costTier: CostTier {
        switch self {
        case .gpt5:
            return .high
        case .gpt5Mini:
            return .medium
        case .gpt5Nano:
            return .low
        }
    }

    /// Cost tier categories.
    public enum CostTier: String, Sendable {
        case low
        case medium
        case high
        case veryHigh
    }
}

// MARK: - CustomStringConvertible

extension ResponsesModel: CustomStringConvertible {
    public var description: String {
        return name
    }
}

// MARK: - Convenience Accessors

extension ResponsesModel {
    /// The default recommended Responses model.
    public static var `default`: ResponsesModel {
        return .gpt5
    }

    /// The fastest available model.
    public static var fastest: ResponsesModel {
        return .gpt5Nano
    }

    /// The most capable available model.
    public static var mostCapable: ResponsesModel {
        return .gpt5
    }

    /// The most affordable model.
    public static var mostAffordable: ResponsesModel {
        return .gpt5Nano
    }

    /// Recommended model for structured outputs.
    public static var forStructuredOutputs: ResponsesModel {
        return .gpt5
    }

    /// Recommended model for vision tasks.
    public static var forVision: ResponsesModel {
        return .gpt5
    }
}
