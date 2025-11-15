// RequestBuilder.swift
// Echo - Network Layer
// Helper for building WebSocket request messages for the Realtime API

import Foundation

/// Builds JSON request messages for the Realtime API WebSocket protocol
public struct RequestBuilder {
    /// Builds a session.update event
    /// - Parameters:
    ///   - session: The session configuration parameters
    /// - Returns: JSON string to send over WebSocket
    public static func buildSessionUpdate(session: SendableJSON) throws -> String {
        let sessionDict = try session.toDictionary()
        let payload: [String: Any] = [
            "type": "session.update",
            "session": sessionDict
        ]
        return try toJSON(payload)
    }

    /// Builds a session.update event from raw dictionary
    /// - Parameters:
    ///   - sessionDict: The session configuration dictionary (preserves NSDecimalNumber for temperature)
    /// - Returns: JSON string to send over WebSocket
    public static func buildSessionUpdate(sessionDict: [String: Any]) throws -> String {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": sessionDict
        ]
        return try toJSON(payload)
    }

    /// Builds an input_audio_buffer.append event
    /// - Parameter audio: Base64-encoded audio data
    /// - Returns: JSON string to send over WebSocket
    public static func buildInputAudioBufferAppend(audio: String) throws -> String {
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": audio
        ]
        return try toJSON(payload)
    }

    /// Builds an input_audio_buffer.commit event
    /// - Returns: JSON string to send over WebSocket
    public static func buildInputAudioBufferCommit() throws -> String {
        let payload: [String: String] = [
            "type": "input_audio_buffer.commit"
        ]
        return try toJSON(payload)
    }

    /// Builds an input_audio_buffer.clear event
    /// - Returns: JSON string to send over WebSocket
    public static func buildInputAudioBufferClear() throws -> String {
        let payload: [String: String] = [
            "type": "input_audio_buffer.clear"
        ]
        return try toJSON(payload)
    }

    /// Builds a conversation.item.create event
    /// - Parameters:
    ///   - item: The conversation item to create
    ///   - previousItemId: Optional ID of the item to insert after
    /// - Returns: JSON string to send over WebSocket
    public static func buildConversationItemCreate(
        item: SendableJSON,
        previousItemId: String? = nil
    ) throws -> String {
        let itemDict = try item.toDictionary()
        var payload: [String: Any] = [
            "type": "conversation.item.create",
            "item": itemDict
        ]
        if let previousItemId = previousItemId {
            payload["previous_item_id"] = previousItemId
        }
        return try toJSON(payload)
    }

    /// Builds a conversation.item.truncate event
    /// - Parameters:
    ///   - itemId: The ID of the item to truncate
    ///   - contentIndex: The content part index to truncate
    ///   - audioEnd: The audio sample index to truncate at
    /// - Returns: JSON string to send over WebSocket
    public static func buildConversationItemTruncate(
        itemId: String,
        contentIndex: Int,
        audioEnd: Int
    ) throws -> String {
        let payload: [String: Any] = [
            "type": "conversation.item.truncate",
            "item_id": itemId,
            "content_index": contentIndex,
            "audio_end_ms": audioEnd
        ]
        return try toJSON(payload)
    }

    /// Builds a conversation.item.delete event
    /// - Parameter itemId: The ID of the item to delete
    /// - Returns: JSON string to send over WebSocket
    public static func buildConversationItemDelete(itemId: String) throws -> String {
        let payload: [String: String] = [
            "type": "conversation.item.delete",
            "item_id": itemId
        ]
        return try toJSON(payload)
    }

    /// Builds a response.create event
    /// - Parameter response: Optional response configuration
    /// - Returns: JSON string to send over WebSocket
    public static func buildResponseCreate(response: SendableJSON? = nil) throws -> String {
        var payload: [String: Any] = [
            "type": "response.create"
        ]
        if let response = response {
            let responseDict = try response.toDictionary()
            payload["response"] = responseDict
        }
        return try toJSON(payload)
    }

    /// Builds a response.cancel event
    /// - Returns: JSON string to send over WebSocket
    public static func buildResponseCancel() throws -> String {
        let payload: [String: String] = [
            "type": "response.cancel"
        ]
        return try toJSON(payload)
    }

    // MARK: - Private Helpers

    private static func toJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []  // Compact JSON
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw RequestBuilderError.encodingFailed
        }
        return json
    }

    private static func toJSON(_ dictionary: [String: Any]) throws -> String {
        // Check if we need to handle temperature specially
        var processedDict = dictionary
        if let type = dictionary["type"] as? String, type == "session.update",
           var session = dictionary["session"] as? [String: Any],
           let tempString = session["__temperature_string"] as? String {
            // Remove the marker key and add proper temperature as decimal number
            session.removeValue(forKey: "__temperature_string")
            // Convert string to NSDecimalNumber to preserve exact decimal representation
            if let decimal = Decimal(string: tempString) {
                session["temperature"] = NSDecimalNumber(decimal: decimal)
            }
            processedDict["session"] = session
        }

        let data = try JSONSerialization.data(withJSONObject: processedDict, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw RequestBuilderError.encodingFailed
        }

        // Debug logging for session.update events to see exact JSON being sent
        if let type = processedDict["type"] as? String, type == "session.update" {
            print("[RequestBuilder] 📤 Sending session.update JSON: \(json)")
        }

        return json
    }
}

// MARK: - Request Builder Errors

public enum RequestBuilderError: Error, LocalizedError {
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode request to JSON"
        }
    }
}
