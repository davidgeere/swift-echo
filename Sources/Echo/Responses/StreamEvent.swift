// StreamEvent.swift
// Echo - Responses API
// SSE delta events for streaming responses

import Foundation

/// Represents a streaming event from the Responses API (SSE)
public enum StreamEvent: Codable, Sendable {
    // MARK: - Response Events

    /// Response creation started
    case responseCreated(id: String)

    /// Text content delta (incremental chunk)
    case responseDelta(delta: String)

    /// Response completed successfully
    case responseDone(response: ResponsesResponse)

    /// Response was cancelled
    case responseCancelled

    /// Response failed with error
    case responseFailed(error: String)

    // MARK: - Tool Call Events

    /// Tool call was requested
    case toolCallDelta(id: String, name: String, argumentsDelta: String)

    /// Tool call arguments completed
    case toolCallDone(id: String, name: String, arguments: String)

    // MARK: - Usage Events

    /// Token usage information
    case usageUpdate(inputTokens: Int, outputTokens: Int)

    // MARK: - Raw Event

    /// Raw event data (for events we don't explicitly handle)
    case raw(type: String, data: [String: AnyCodable])

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case delta
        case response
        case error
        case name
        case argumentsDelta = "arguments_delta"
        case arguments
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case data
        case sequenceNumber = "sequence_number"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case text
        case item
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "response.created":
            // id is nested in response.id
            let responseContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .response)
            let id = try responseContainer.decode(String.self, forKey: .id)
            self = .responseCreated(id: id)

        case "response.output_text.delta":
            // Extract delta from nested structure
            let delta = try container.decode(String.self, forKey: .delta)
            self = .responseDelta(delta: delta)

        case "response.completed":
            // Extract response from nested structure
            let response = try container.decode(ResponsesResponse.self, forKey: .response)
            self = .responseDone(response: response)

        case "response.cancelled":
            self = .responseCancelled

        case "response.failed":
            let error = try container.decode(String.self, forKey: .error)
            self = .responseFailed(error: error)

        case "tool_call.delta":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let argumentsDelta = try container.decode(String.self, forKey: .argumentsDelta)
            self = .toolCallDelta(id: id, name: name, argumentsDelta: argumentsDelta)
        
        case "tool_call.done":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let arguments = try container.decode(String.self, forKey: .arguments)
            self = .toolCallDone(id: id, name: name, arguments: arguments)
            
        case "response.function_call_arguments.delta":
            // Handle the actual format from OpenAI's API
            // The delta comes directly as a field, not nested
            if let delta = try? container.decode(String.self, forKey: .delta),
               let itemId = try? container.decode(String.self, forKey: .itemId) {
                // We don't have the name here, we'll need to track it from output_item.added
                // For now, use the itemId as the id and empty name
                self = .toolCallDelta(id: itemId, name: "", argumentsDelta: delta)
            } else {
                // Fall back to raw if we can't parse it
                let data: [String: AnyCodable] = [:]
                self = .raw(type: type, data: data)
            }
            
        case "response.function_call_arguments.done":
            // Handle the completion
            if let arguments = try? container.decode(String.self, forKey: .arguments),
               let itemId = try? container.decode(String.self, forKey: .itemId) {
                // Use itemId as the id and empty name (will be filled later)
                self = .toolCallDone(id: itemId, name: "", arguments: arguments)
            } else {
                // Fall back to raw if we can't parse it
                let data: [String: AnyCodable] = [:]
                self = .raw(type: type, data: data)
            }

        case "usage.update":
            let inputTokens = try container.decode(Int.self, forKey: .inputTokens)
            let outputTokens = try container.decode(Int.self, forKey: .outputTokens)
            self = .usageUpdate(inputTokens: inputTokens, outputTokens: outputTokens)

        case "response.output_item.added":
            // This event contains function call metadata including the name
            // We need to capture it to match with function_call_arguments events
            var data: [String: AnyCodable] = [:]
            
            // Try to extract the item info
            if let item = try? container.decode([String: AnyCodable].self, forKey: .item) {
                data["item"] = AnyCodable(item)
            }
            self = .raw(type: type, data: data)
            
        case "response.in_progress",
             "response.output_item.done",
             "response.content_part.added",
             "response.content_part.done",
             "response.output_text.done":
            // These events don't affect our current functionality - silently ignore
            self = .raw(type: type, data: [:])

        default:
            // Unknown event type - try to decode data if present, otherwise use empty dict
            let data = (try? container.decode([String: AnyCodable].self, forKey: .data)) ?? [:]
            self = .raw(type: type, data: data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .responseCreated(let id):
            try container.encode("response.created", forKey: .type)
            try container.encode(id, forKey: .id)

        case .responseDelta(let delta):
            try container.encode("response.delta", forKey: .type)
            try container.encode(delta, forKey: .delta)

        case .responseDone(let response):
            try container.encode("response.done", forKey: .type)
            try container.encode(response, forKey: .response)

        case .responseCancelled:
            try container.encode("response.cancelled", forKey: .type)

        case .responseFailed(let error):
            try container.encode("response.failed", forKey: .type)
            try container.encode(error, forKey: .error)

        case .toolCallDelta(let id, let name, let argumentsDelta):
            try container.encode("tool_call.delta", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(argumentsDelta, forKey: .argumentsDelta)

        case .toolCallDone(let id, let name, let arguments):
            try container.encode("tool_call.done", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)

        case .usageUpdate(let inputTokens, let outputTokens):
            try container.encode("usage.update", forKey: .type)
            try container.encode(inputTokens, forKey: .inputTokens)
            try container.encode(outputTokens, forKey: .outputTokens)

        case .raw(let type, let data):
            try container.encode(type, forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable value for handling dynamic JSON
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
