// Base64Encoder.swift

import Foundation

/// Base64 encoding utilities for audio data
public struct Base64Encoder: Sendable {
    /// Encode data to base64 string
    public static func encode(_ data: Data) -> String {
        return data.base64EncodedString()
    }

    /// Decode base64 string to data
    public static func decode(_ string: String) throws -> Data {
        guard let data = Data(base64Encoded: string) else {
            throw Base64Error.invalidBase64String
        }
        return data
    }

    /// Encode data to base64 with options
    public static func encode(_ data: Data, options: Data.Base64EncodingOptions) -> String {
        return data.base64EncodedString(options: options)
    }

    /// Decode base64 string to data with options
    public static func decode(_ string: String, options: Data.Base64DecodingOptions) throws -> Data {
        guard let data = Data(base64Encoded: string, options: options) else {
            throw Base64Error.invalidBase64String
        }
        return data
    }
}

public enum Base64Error: Error {
    case invalidBase64String
}
