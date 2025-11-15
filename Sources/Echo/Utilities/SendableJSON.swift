// SendableJSON.swift
// Echo - Utilities
// Sendable-compliant JSON type wrapper

import Foundation

/// A Sendable-compliant JSON value
public enum SendableJSON: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([SendableJSON])
    case object([String: SendableJSON])

    /// Create from a dictionary
    public static func from(dictionary: [String: Any]) throws -> SendableJSON {
        var result: [String: SendableJSON] = [:]
        for (key, value) in dictionary {
            result[key] = try from(value: value)
        }
        return .object(result)
    }

    /// Create from any value
    public static func from(value: Any) throws -> SendableJSON {
        switch value {
        case let string as String:
            return .string(string)
        case let number as Int:
            return .number(Double(number))
        case let number as Double:
            return .number(number)
        case let bool as Bool:
            return .bool(bool)
        case is NSNull:
            return .null
        case let array as [Any]:
            return .array(try array.map { try from(value: $0) })
        case let dict as [String: Any]:
            return try from(dictionary: dict)
        default:
            throw SendableJSONError.unsupportedType
        }
    }

    /// Convert to dictionary
    public func toDictionary() throws -> [String: Any] {
        guard case .object(let dict) = self else {
            throw SendableJSONError.notAnObject
        }
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = try value.toAny()
        }
        return result
    }

    /// Convert to Any
    public func toAny() throws -> Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .array(let values):
            return try values.map { try $0.toAny() }
        case .object(let dict):
            return try dict.mapValues { try $0.toAny() }
        }
    }

    /// Convert to Data
    public func toData() throws -> Data {
        let anyValue = try toAny()
        return try JSONSerialization.data(withJSONObject: anyValue)
    }

    /// Create from Data
    public static func from(data: Data) throws -> SendableJSON {
        let value = try JSONSerialization.jsonObject(with: data)
        return try from(value: value)
    }
}

/// Errors for SendableJSON
public enum SendableJSONError: Error {
    case invalidFormat
    case serializationFailed
    case unsupportedType
    case notAnObject
}

// MARK: - Codable Support

extension SendableJSON: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else if let array = try? container.decode([SendableJSON].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: SendableJSON].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode SendableJSON"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}
