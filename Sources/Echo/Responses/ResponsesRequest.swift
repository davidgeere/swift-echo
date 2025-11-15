// ResponsesRequest.swift
// Echo - Responses API
// Request structure for creating responses

import Foundation

/// Request structure for creating a response via the Responses API
public struct ResponsesRequest: Encodable, Sendable {
    // MARK: - Required Fields

    /// The model to use (must be gpt-5, gpt-5-mini, or gpt-5-nano)
    public let model: String

    /// Input - can be a string or array of messages
    public let input: InputContent

    public enum InputContent: Encodable, Sendable {
        case string(String)
        case messages([InputMessage])

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let str):
                try container.encode(str)
            case .messages(let msgs):
                try container.encode(msgs)
            }
        }
    }

    // MARK: - Optional Fields

    /// System instructions (optional)
    public let instructions: String?

    /// Tools available for function calling (optional)
    public let tools: [ResponsesTool]?

    /// Tool choice configuration
    public let toolChoice: String?

    /// Response format (for structured outputs)
    public let responseFormat: ResponseFormat?

    /// Temperature for sampling (0.0 - 2.0)
    public let temperature: Double?

    /// Top-p sampling
    public let topP: Double?

    /// Maximum output tokens
    public let maxOutputTokens: Int?

    /// Stop sequences
    public let stop: [String]?

    /// Whether to stream the response
    public let stream: Bool
    
    /// Reasoning configuration (nested object with effort level)
    public let reasoning: ReasoningConfig?

    /// Metadata for request tracking
    public let metadata: [String: String]?
    
    /// Nested reasoning configuration
    public struct ReasoningConfig: Encodable, Sendable {
        public let effort: String
        
        public init(effort: String) {
            self.effort = effort
        }
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case tools
        case toolChoice = "tool_choice"
        case text  // For the new API format
        case temperature
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
        case stop
        case stream
        case reasoning
        case metadata
    }
    
    // Nested key for text.format
    enum TextCodingKeys: String, CodingKey {
        case format
    }
    
    // MARK: - Custom Encoding
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode required fields
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        
        // Encode optional fields
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encodeIfPresent(stop, forKey: .stop)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        
        // Special handling for responseFormat - needs to be nested under "text.format"
        if let responseFormat = responseFormat {
            var textContainer = container.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .text)
            try textContainer.encode(responseFormat, forKey: .format)
        }
    }

    // MARK: - Initialization

    public init(
        model: String,
        input: InputContent,
        instructions: String? = nil,
        tools: [ResponsesTool]? = nil,
        toolChoice: String? = nil,
        responseFormat: ResponseFormat? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        stop: [String]? = nil,
        stream: Bool = false,
        reasoningEffort: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
        self.responseFormat = responseFormat
        self.temperature = temperature
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
        self.stop = stop
        self.stream = stream
        self.reasoning = reasoningEffort.map { ReasoningConfig(effort: $0) }
        self.metadata = metadata
    }
}

// Note: Supporting types are defined in separate files:
// - InputMessage.swift
// - ResponsesMessage.swift
// - MessageContentPart.swift
// - ResponsesTool.swift (with nested FunctionDefinition)
// - ResponseFormat.swift
// - JSONSchema.swift
