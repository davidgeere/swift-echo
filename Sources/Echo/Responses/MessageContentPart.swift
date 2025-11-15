// MessageContentPart.swift
// Echo - Responses API
// Content part in a message (can be text, image, etc.)

import Foundation

/// Content part in a message (can be text, image, etc.)
public enum MessageContentPart: Codable, Sendable {
    case text(String)
    case imageURL(String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text", "output_text":  // API uses "output_text" in responses
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image_url":
            let url = try container.decode(String.self, forKey: .imageURL)
            self = .imageURL(url)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content part type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(url, forKey: .imageURL)
        }
    }
}
