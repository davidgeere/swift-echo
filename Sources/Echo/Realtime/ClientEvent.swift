// ClientEvent.swift
// Echo - Realtime API
// Client events sent TO the Realtime API server (9 event types)

import Foundation

/// Events that the client sends to the Realtime API server
public enum ClientEvent: Sendable {
    // MARK: - Session Events (1)

    /// Updates the session configuration
    /// - Parameter session: Session configuration parameters
    case sessionUpdate(session: SendableJSON)

    // MARK: - Input Audio Buffer Events (3)

    /// Appends audio data to the input buffer
    /// - Parameter audio: Base64-encoded audio data
    case inputAudioBufferAppend(audio: String)

    /// Commits the audio buffer and triggers processing
    case inputAudioBufferCommit

    /// Clears the audio buffer
    case inputAudioBufferClear

    // MARK: - Conversation Events (3)

    /// Creates a new conversation item
    /// - Parameters:
    ///   - item: The conversation item data
    ///   - previousItemId: Optional ID to insert after
    case conversationItemCreate(item: SendableJSON, previousItemId: String?)

    /// Truncates a conversation item's audio
    /// - Parameters:
    ///   - itemId: The item ID to truncate
    ///   - contentIndex: The content part index
    ///   - audioEnd: The audio sample index to truncate at
    case conversationItemTruncate(itemId: String, contentIndex: Int, audioEnd: Int)

    /// Deletes a conversation item
    /// - Parameter itemId: The item ID to delete
    case conversationItemDelete(itemId: String)

    // MARK: - Response Events (2)

    /// Triggers a new response generation
    /// - Parameter response: Optional response configuration
    case responseCreate(response: SendableJSON?)

    /// Cancels an in-progress response
    case responseCancel

    // MARK: - Conversion

    /// Converts the event to JSON string for transmission
    /// - Returns: JSON string representation
    /// - Throws: RequestBuilderError if encoding fails
    public func toJSON() throws -> String {
        switch self {
        case .sessionUpdate(let session):
            return try RequestBuilder.buildSessionUpdate(session: session)

        case .inputAudioBufferAppend(let audio):
            return try RequestBuilder.buildInputAudioBufferAppend(audio: audio)

        case .inputAudioBufferCommit:
            return try RequestBuilder.buildInputAudioBufferCommit()

        case .inputAudioBufferClear:
            return try RequestBuilder.buildInputAudioBufferClear()

        case .conversationItemCreate(let item, let previousItemId):
            return try RequestBuilder.buildConversationItemCreate(
                item: item,
                previousItemId: previousItemId
            )

        case .conversationItemTruncate(let itemId, let contentIndex, let audioEnd):
            return try RequestBuilder.buildConversationItemTruncate(
                itemId: itemId,
                contentIndex: contentIndex,
                audioEnd: audioEnd
            )

        case .conversationItemDelete(let itemId):
            return try RequestBuilder.buildConversationItemDelete(itemId: itemId)

        case .responseCreate(let response):
            return try RequestBuilder.buildResponseCreate(response: response)

        case .responseCancel:
            return try RequestBuilder.buildResponseCancel()
        }
    }

    // MARK: - Type Name

    /// The event type name for logging/debugging
    public var typeName: String {
        switch self {
        case .sessionUpdate:
            return "session.update"
        case .inputAudioBufferAppend:
            return "input_audio_buffer.append"
        case .inputAudioBufferCommit:
            return "input_audio_buffer.commit"
        case .inputAudioBufferClear:
            return "input_audio_buffer.clear"
        case .conversationItemCreate:
            return "conversation.item.create"
        case .conversationItemTruncate:
            return "conversation.item.truncate"
        case .conversationItemDelete:
            return "conversation.item.delete"
        case .responseCreate:
            return "response.create"
        case .responseCancel:
            return "response.cancel"
        }
    }
}

// MARK: - CustomStringConvertible

extension ClientEvent: CustomStringConvertible {
    public var description: String {
        return typeName
    }
}
