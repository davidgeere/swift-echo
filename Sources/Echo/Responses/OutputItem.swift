// OutputItem.swift
// Echo - Responses API
// Output item (can be a message or reasoning)

import Foundation

/// Output item (can be a message or reasoning)
public enum OutputItem: Codable, Sendable {
    case message(ResponsesMessage)
    case reasoning(id: String)
    case unknown

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case role
        case content
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message":
            // Decode as ResponsesMessage
            let message = try ResponsesMessage(from: decoder)
            self = .message(message)
        case "reasoning":
            // Just extract the ID, ignore the rest
            let id = try container.decode(String.self, forKey: .id)
            self = .reasoning(id: id)
        default:
            // Unknown type - skip it
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let message):
            try message.encode(to: encoder)
        case .reasoning(let id):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("reasoning", forKey: .type)
            try container.encode(id, forKey: .id)
        case .unknown:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("unknown", forKey: .type)
        }
    }
}
