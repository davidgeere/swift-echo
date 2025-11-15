import Foundation

/// Describes the capabilities of an AI model.
///
/// ModelCapabilities provides a structured way to query what features
/// a specific model supports, enabling runtime checks and appropriate
/// fallback behavior when certain features aren't available.
public struct ModelCapabilities: Sendable, Codable {
    // MARK: - Core Capabilities

    /// Whether the model supports audio input/output.
    /// Only Realtime API models support audio.
    public let supportsAudio: Bool

    /// Whether the model supports streaming responses.
    /// Both Realtime and Responses APIs support streaming.
    public let supportsStreaming: Bool

    /// Whether the model supports function/tool calling.
    /// Most modern models support this feature.
    public let supportsTools: Bool

    /// Whether the model supports structured JSON outputs.
    /// Only certain Responses API models support this.
    public let supportsStructuredOutputs: Bool

    /// Whether the model supports vision/image inputs.
    /// GPT-4o and GPT-4 Turbo variants support vision.
    public let supportsVision: Bool

    // MARK: - Token Limits

    /// Maximum context window size in tokens.
    /// This is the total number of tokens (input + output) the model can process.
    public let maxContextTokens: Int

    /// Maximum output tokens per response.
    /// This is the maximum number of tokens the model can generate in a single response.
    public let maxOutputTokens: Int

    // MARK: - Additional Features

    /// Whether the model supports multimodal inputs (text + images + audio).
    public var isMultimodal: Bool {
        return supportsVision || supportsAudio
    }

    /// Estimated input cost per 1K tokens (in USD).
    /// This is a rough estimate and actual costs may vary.
    public var estimatedInputCostPer1K: Double?

    /// Estimated output cost per 1K tokens (in USD).
    /// This is a rough estimate and actual costs may vary.
    public var estimatedOutputCostPer1K: Double?

    // MARK: - Initialization

    /// Creates a new model capabilities description.
    ///
    /// - Parameters:
    ///   - supportsAudio: Whether audio I/O is supported
    ///   - supportsStreaming: Whether streaming is supported
    ///   - supportsTools: Whether tool/function calling is supported
    ///   - supportsStructuredOutputs: Whether structured outputs are supported
    ///   - supportsVision: Whether vision/image inputs are supported
    ///   - maxContextTokens: Maximum context window size
    ///   - maxOutputTokens: Maximum output tokens
    ///   - estimatedInputCostPer1K: Estimated input cost per 1K tokens (optional)
    ///   - estimatedOutputCostPer1K: Estimated output cost per 1K tokens (optional)
    public init(
        supportsAudio: Bool,
        supportsStreaming: Bool,
        supportsTools: Bool,
        supportsStructuredOutputs: Bool,
        supportsVision: Bool,
        maxContextTokens: Int,
        maxOutputTokens: Int,
        estimatedInputCostPer1K: Double? = nil,
        estimatedOutputCostPer1K: Double? = nil
    ) {
        self.supportsAudio = supportsAudio
        self.supportsStreaming = supportsStreaming
        self.supportsTools = supportsTools
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.supportsVision = supportsVision
        self.maxContextTokens = maxContextTokens
        self.maxOutputTokens = maxOutputTokens
        self.estimatedInputCostPer1K = estimatedInputCostPer1K
        self.estimatedOutputCostPer1K = estimatedOutputCostPer1K
    }

    // MARK: - Validation

    /// Checks if the model can handle a specific feature requirement.
    public func supports(feature: Feature) -> Bool {
        switch feature {
        case .audio:
            return supportsAudio
        case .streaming:
            return supportsStreaming
        case .tools:
            return supportsTools
        case .structuredOutputs:
            return supportsStructuredOutputs
        case .vision:
            return supportsVision
        case .multimodal:
            return isMultimodal
        }
    }

    /// Checks if the model can handle a specific number of tokens.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens (optional)
    /// - Returns: Whether the model can handle this token count
    public func canHandle(inputTokens: Int, outputTokens: Int? = nil) -> Bool {
        let totalTokens = inputTokens + (outputTokens ?? maxOutputTokens)
        return totalTokens <= maxContextTokens
    }

    /// Estimates the cost for a given number of tokens.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - outputTokens: Number of output tokens
    /// - Returns: Estimated cost in USD, or nil if cost data is unavailable
    public func estimateCost(inputTokens: Int, outputTokens: Int) -> Double? {
        guard let inputCost = estimatedInputCostPer1K,
              let outputCost = estimatedOutputCostPer1K else {
            return nil
        }

        let inputCostTotal = (Double(inputTokens) / 1000.0) * inputCost
        let outputCostTotal = (Double(outputTokens) / 1000.0) * outputCost

        return inputCostTotal + outputCostTotal
    }

    // MARK: - Feature Enum

    /// Features that models may support.
    public enum Feature: String, Sendable, CaseIterable {
        /// Audio input/output capability.
        case audio

        /// Streaming response capability.
        case streaming

        /// Function/tool calling capability.
        case tools

        /// Structured JSON outputs capability.
        case structuredOutputs

        /// Vision/image input capability.
        case vision

        /// Any multimodal input capability.
        case multimodal
    }
}

// MARK: - Equatable

extension ModelCapabilities: Equatable {
    public static func == (lhs: ModelCapabilities, rhs: ModelCapabilities) -> Bool {
        return lhs.supportsAudio == rhs.supportsAudio &&
               lhs.supportsStreaming == rhs.supportsStreaming &&
               lhs.supportsTools == rhs.supportsTools &&
               lhs.supportsStructuredOutputs == rhs.supportsStructuredOutputs &&
               lhs.supportsVision == rhs.supportsVision &&
               lhs.maxContextTokens == rhs.maxContextTokens &&
               lhs.maxOutputTokens == rhs.maxOutputTokens
    }
}

// MARK: - CustomStringConvertible

extension ModelCapabilities: CustomStringConvertible {
    public var description: String {
        var features: [String] = []

        if supportsAudio { features.append("Audio") }
        if supportsVision { features.append("Vision") }
        if supportsTools { features.append("Tools") }
        if supportsStructuredOutputs { features.append("Structured Outputs") }
        if supportsStreaming { features.append("Streaming") }

        let featuresStr = features.joined(separator: ", ")
        return "Capabilities: \(featuresStr) | Context: \(maxContextTokens) tokens | Output: \(maxOutputTokens) tokens"
    }
}

// MARK: - Preset Capabilities

extension ModelCapabilities {
    /// Capabilities for GPT-4o Realtime models.
    public static let gpt4oRealtime = ModelCapabilities(
        supportsAudio: true,
        supportsStreaming: true,
        supportsTools: true,
        supportsStructuredOutputs: false,
        supportsVision: false,
        maxContextTokens: 128_000,
        maxOutputTokens: 16_384,
        estimatedInputCostPer1K: 0.005,
        estimatedOutputCostPer1K: 0.015
    )

    /// Capabilities for GPT-4o text models.
    public static let gpt4o = ModelCapabilities(
        supportsAudio: false,
        supportsStreaming: true,
        supportsTools: true,
        supportsStructuredOutputs: true,
        supportsVision: true,
        maxContextTokens: 128_000,
        maxOutputTokens: 16_384,
        estimatedInputCostPer1K: 0.0025,
        estimatedOutputCostPer1K: 0.01
    )

    /// Capabilities for GPT-4o Mini models.
    public static let gpt4oMini = ModelCapabilities(
        supportsAudio: false,
        supportsStreaming: true,
        supportsTools: true,
        supportsStructuredOutputs: true,
        supportsVision: true,
        maxContextTokens: 128_000,
        maxOutputTokens: 16_384,
        estimatedInputCostPer1K: 0.00015,
        estimatedOutputCostPer1K: 0.0006
    )

    /// Capabilities for GPT-4 Turbo models.
    public static let gpt4Turbo = ModelCapabilities(
        supportsAudio: false,
        supportsStreaming: true,
        supportsTools: true,
        supportsStructuredOutputs: false,
        supportsVision: true,
        maxContextTokens: 128_000,
        maxOutputTokens: 4_096,
        estimatedInputCostPer1K: 0.01,
        estimatedOutputCostPer1K: 0.03
    )

    /// Capabilities for GPT-3.5 Turbo models.
    public static let gpt35Turbo = ModelCapabilities(
        supportsAudio: false,
        supportsStreaming: true,
        supportsTools: true,
        supportsStructuredOutputs: false,
        supportsVision: false,
        maxContextTokens: 16_385,
        maxOutputTokens: 4_096,
        estimatedInputCostPer1K: 0.0005,
        estimatedOutputCostPer1K: 0.0015
    )
}
