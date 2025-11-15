import Foundation

/// Unified model wrapper for both Realtime and Responses APIs.
///
/// EchoModel provides a unified interface for working with different AI models
/// across both audio (Realtime API) and text (Responses API) modes.
public enum EchoModel: Sendable, Codable {
    /// Realtime API model for audio conversations.
    case realtime(RealtimeModel)

    /// Responses API model for text conversations.
    case responses(ResponsesModel)

    // MARK: - Computed Properties

    /// The raw model identifier string.
    public var identifier: String {
        switch self {
        case .realtime(let model):
            return model.rawValue
        case .responses(let model):
            return model.rawValue
        }
    }

    /// Whether this model supports audio input/output.
    public var supportsAudio: Bool {
        switch self {
        case .realtime:
            return true
        case .responses:
            return false
        }
    }

    /// Whether this model supports streaming responses.
    public var supportsStreaming: Bool {
        return true // Both APIs support streaming
    }

    /// Whether this model supports function/tool calling.
    public var supportsTools: Bool {
        return true // Both APIs support tools
    }

    /// Whether this model supports structured outputs.
    public var supportsStructuredOutputs: Bool {
        switch self {
        case .realtime:
            return false // Realtime API doesn't support structured outputs
        case .responses:
            return true
        }
    }

    /// The mode this model is designed for.
    public var mode: EchoMode {
        switch self {
        case .realtime:
            return .audio
        case .responses:
            return .text
        }
    }

    // MARK: - Capabilities

    /// Get the capabilities for this model.
    public var capabilities: ModelCapabilities {
        switch self {
        case .realtime(let model):
            return model.capabilities
        case .responses(let model):
            return model.capabilities
        }
    }

    // MARK: - Codable Implementation

    enum CodingKeys: String, CodingKey {
        case type
        case model
    }

    enum ModelType: String, Codable {
        case realtime
        case responses
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .realtime(let model):
            try container.encode(ModelType.realtime, forKey: .type)
            try container.encode(model, forKey: .model)

        case .responses(let model):
            try container.encode(ModelType.responses, forKey: .type)
            try container.encode(model, forKey: .model)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ModelType.self, forKey: .type)

        switch type {
        case .realtime:
            let model = try container.decode(RealtimeModel.self, forKey: .model)
            self = .realtime(model)

        case .responses:
            let model = try container.decode(ResponsesModel.self, forKey: .model)
            self = .responses(model)
        }
    }
}

// MARK: - Convenience Initializers

extension EchoModel {
    /// Validates and creates a model from a string identifier.
    /// Throws an error if the model is not one of the 5 supported models.
    /// - Parameter modelString: The model identifier (e.g., "gpt-realtime", "gpt-5")
    /// - Returns: A validated EchoModel instance
    /// - Throws: EchoError.unsupportedModel if the model is not supported
    public static func validate(_ modelString: String) throws -> EchoModel {
        if let realtimeModel = RealtimeModel(rawValue: modelString) {
            return .realtime(realtimeModel)
        }
        if let responsesModel = ResponsesModel(rawValue: modelString) {
            return .responses(responsesModel)
        }
        throw EchoError.unsupportedModel(
            "Model '\(modelString)' is not supported. " +
            "Valid models: gpt-realtime, gpt-realtime-mini, gpt-5, gpt-5-mini, gpt-5-nano"
        )
    }

    /// Creates a model from a string identifier.
    /// Automatically determines whether it's a Realtime or Responses model.
    public static func from(identifier: String) -> EchoModel? {
        // Try Realtime models first
        if let realtimeModel = RealtimeModel(rawValue: identifier) {
            return .realtime(realtimeModel)
        }

        // Try Responses models
        if let responsesModel = ResponsesModel(rawValue: identifier) {
            return .responses(responsesModel)
        }

        return nil
    }

    /// The default Realtime model.
    public static var defaultRealtime: EchoModel {
        .realtime(.gptRealtime)
    }

    /// The default Responses model.
    public static var defaultResponses: EchoModel {
        .responses(.gpt5)
    }
}

// MARK: - Equatable

extension EchoModel: Equatable {
    public static func == (lhs: EchoModel, rhs: EchoModel) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

// MARK: - CustomStringConvertible

extension EchoModel: CustomStringConvertible {
    public var description: String {
        return identifier
    }
}
