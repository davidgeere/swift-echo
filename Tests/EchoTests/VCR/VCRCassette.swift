// VCRCassette.swift
// Echo Tests - VCR Infrastructure
// Cassette for recording and playing back HTTP interactions

import Foundation

/// Represents a recorded HTTP interaction
public struct VCRInteraction: Codable, Sendable {
    /// Recorded request
    public let request: RecordedRequest

    /// Recorded response
    public let response: RecordedResponse

    /// Request details
    public struct RecordedRequest: Codable, Sendable {
        public let endpoint: String
        public let method: String
        public let bodyJSON: String?

        public init(endpoint: String, method: String, bodyJSON: String?) {
            self.endpoint = endpoint
            self.method = method
            self.bodyJSON = bodyJSON
        }
    }

    /// Response details
    public struct RecordedResponse: Codable, Sendable {
        public let statusCode: Int
        public let bodyJSON: String
        public let headers: [String: String]

        public init(statusCode: Int, bodyJSON: String, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.bodyJSON = bodyJSON
            self.headers = headers
        }
    }

    public init(request: RecordedRequest, response: RecordedResponse) {
        self.request = request
        self.response = response
    }
}

/// A cassette containing recorded interactions
public struct VCRCassette: Codable, Sendable {
    /// Name of the cassette
    public let name: String

    /// Recorded interactions
    public var interactions: [VCRInteraction]

    public init(name: String, interactions: [VCRInteraction] = []) {
        self.name = name
        self.interactions = interactions
    }

    /// Find a matching interaction for a request
    public func findInteraction(endpoint: String, method: String, bodyJSON: String?) -> VCRInteraction? {
        return interactions.first { interaction in
            interaction.request.endpoint == endpoint &&
            interaction.request.method == method &&
            interaction.request.bodyJSON == bodyJSON
        }
    }

    /// Add a new interaction to the cassette
    public mutating func record(_ interaction: VCRInteraction) {
        interactions.append(interaction)
    }

    /// Load cassette from JSON file
    public static func load(name: String, from directory: URL) throws -> VCRCassette {
        let fileURL = directory.appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(VCRCassette.self, from: data)
    }

    /// Save cassette to JSON file
    public func save(to directory: URL) throws {
        let fileURL = directory.appendingPathComponent("\(name).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: fileURL)
    }
}
