// ServerEvent.swift
// Echo - Realtime API
// Server events received FROM the Realtime API (28 event types)

import Foundation

/// Events received from the Realtime API server
public enum ServerEvent: Sendable {
    // MARK: - Error Event (1)

    /// Server returned an error
    case error(code: String, message: String, eventId: String?)

    // MARK: - Session Events (2)

    /// Session was created
    case sessionCreated(session: SessionInfo)

    /// Session was updated
    case sessionUpdated(session: SessionInfo)

    // MARK: - Conversation Events (2)

    /// Conversation was created
    case conversationCreated(conversation: ConversationInfo)

    /// Conversation item was created
    case conversationItemCreated(item: ConversationItemInfo, previousItemId: String?)

    // MARK: - Input Audio Buffer Events (3)

    /// Audio buffer was committed
    case inputAudioBufferCommitted(itemId: String, previousItemId: String?)

    /// Speech was detected in the audio buffer
    case inputAudioBufferSpeechStarted(itemId: String, audioStartMs: Int)

    /// Speech ended in the audio buffer
    case inputAudioBufferSpeechStopped(itemId: String, audioEndMs: Int)

    // MARK: - Transcription Events (2)

    /// Input audio transcription completed
    case conversationItemInputAudioTranscriptionCompleted(itemId: String, transcript: String)

    /// Input audio transcription failed
    case conversationItemInputAudioTranscriptionFailed(itemId: String, error: ErrorInfo)

    // MARK: - Conversation Item Events (2)

    /// Conversation item was truncated
    case conversationItemTruncated(itemId: String, contentIndex: Int, audioEndMs: Int)

    /// Conversation item was deleted
    case conversationItemDeleted(itemId: String)

    // MARK: - Response Events (5)

    /// Response was created
    case responseCreated(response: ResponseInfo)

    /// Response generation is in progress
    case responseDone(response: ResponseInfo)

    /// Response output item was created
    case responseOutputItemAdded(responseId: String, outputIndex: Int, item: ConversationItemInfo)

    /// Response output item is complete
    case responseOutputItemDone(responseId: String, outputIndex: Int, item: ConversationItemInfo)

    /// Response content part was added
    case responseContentPartAdded(responseId: String, itemId: String, outputIndex: Int, contentIndex: Int, part: ContentPart)

    // MARK: - Audio Response Events (3)

    /// Audio delta (streaming audio chunk)
    case responseAudioDelta(responseId: String, itemId: String, outputIndex: Int, contentIndex: Int, delta: String)

    /// Audio transcript delta (streaming transcript)
    case responseAudioTranscriptDelta(responseId: String, itemId: String, outputIndex: Int, contentIndex: Int, delta: String)

    /// Audio response is complete
    case responseAudioDone(responseId: String, itemId: String, outputIndex: Int, contentIndex: Int)

    // MARK: - Text Response Events (2)

    /// Text delta (streaming text chunk)
    case responseTextDelta(responseId: String, itemId: String, outputIndex: Int, contentIndex: Int, delta: String)

    /// Text response is complete
    case responseTextDone(responseId: String, itemId: String, outputIndex: Int, contentIndex: Int, text: String)

    // MARK: - Function Call Events (3)

    /// Function call arguments delta
    case responseFunctionCallArgumentsDelta(responseId: String, itemId: String, outputIndex: Int, callId: String, delta: String)

    /// Function call arguments are complete
    case responseFunctionCallArgumentsDone(responseId: String, itemId: String, outputIndex: Int, callId: String, name: String, arguments: String)

    /// Function call output item created
    case responseOutputItemDoneWithFunctionCall(responseId: String, outputIndex: Int, item: ConversationItemInfo)

    // MARK: - Rate Limit Events (2)

    /// Rate limits have been updated
    case rateLimitsUpdated(rateLimits: [RateLimitInfo])

    /// Unknown event type (for forward compatibility)
    case unknown(type: String, data: SendableJSON)

    // MARK: - Parsing

    /// Parses a JSON string into a ServerEvent
    /// - Parameter json: The JSON string from the server
    /// - Returns: Parsed ServerEvent
    /// - Throws: RealtimeError if parsing fails
    public static func parse(from json: String) throws -> ServerEvent {
        guard let data = json.data(using: .utf8) else {
            throw RealtimeError.eventDecodingFailed(
                NSError(domain: "ServerEvent", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid JSON string"
                ])
            )
        }

        guard let eventData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = eventData["type"] as? String else {
            throw RealtimeError.eventDecodingFailed(
                NSError(domain: "ServerEvent", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Missing event type"
                ])
            )
        }

        return try parse(type: type, data: eventData)
    }

    private static func parse(type: String, data: [String: Any]) throws -> ServerEvent {
        switch type {
        // Error
        case "error":
            let errorDict = data["error"] as? [String: Any] ?? [:]
            let code = errorDict["code"] as? String ?? "unknown"
            let message = errorDict["message"] as? String ?? "Unknown error"
            let eventId = data["event_id"] as? String
            return .error(code: code, message: message, eventId: eventId)

        // Session
        case "session.created":
            let session = try SessionInfo.parse(from: data["session"] as? [String: Any] ?? [:])
            return .sessionCreated(session: session)

        case "session.updated":
            let session = try SessionInfo.parse(from: data["session"] as? [String: Any] ?? [:])
            return .sessionUpdated(session: session)

        // Conversation
        case "conversation.created":
            let conversation = try ConversationInfo.parse(from: data["conversation"] as? [String: Any] ?? [:])
            return .conversationCreated(conversation: conversation)

        case "conversation.item.created":
            let item = try ConversationItemInfo.parse(from: data["item"] as? [String: Any] ?? [:])
            let previousItemId = data["previous_item_id"] as? String
            return .conversationItemCreated(item: item, previousItemId: previousItemId)

        // Input Audio Buffer
        case "input_audio_buffer.committed":
            let itemId = data["item_id"] as? String ?? ""
            let previousItemId = data["previous_item_id"] as? String
            return .inputAudioBufferCommitted(itemId: itemId, previousItemId: previousItemId)

        case "input_audio_buffer.speech_started":
            let itemId = data["item_id"] as? String ?? ""
            let audioStartMs = data["audio_start_ms"] as? Int ?? 0
            return .inputAudioBufferSpeechStarted(itemId: itemId, audioStartMs: audioStartMs)

        case "input_audio_buffer.speech_stopped":
            let itemId = data["item_id"] as? String ?? ""
            let audioEndMs = data["audio_end_ms"] as? Int ?? 0
            return .inputAudioBufferSpeechStopped(itemId: itemId, audioEndMs: audioEndMs)

        // Transcription
        case "conversation.item.input_audio_transcription.completed":
            let itemId = data["item_id"] as? String ?? ""
            let transcript = data["transcript"] as? String ?? ""
            return .conversationItemInputAudioTranscriptionCompleted(itemId: itemId, transcript: transcript)

        case "conversation.item.input_audio_transcription.failed":
            let itemId = data["item_id"] as? String ?? ""
            let error = try ErrorInfo.parse(from: data["error"] as? [String: Any] ?? [:])
            return .conversationItemInputAudioTranscriptionFailed(itemId: itemId, error: error)

        // Conversation Item Management
        case "conversation.item.truncated":
            let itemId = data["item_id"] as? String ?? ""
            let contentIndex = data["content_index"] as? Int ?? 0
            let audioEndMs = data["audio_end_ms"] as? Int ?? 0
            return .conversationItemTruncated(itemId: itemId, contentIndex: contentIndex, audioEndMs: audioEndMs)

        case "conversation.item.deleted":
            let itemId = data["item_id"] as? String ?? ""
            return .conversationItemDeleted(itemId: itemId)

        // Response
        case "response.created":
            let response = try ResponseInfo.parse(from: data["response"] as? [String: Any] ?? [:])
            return .responseCreated(response: response)

        case "response.done":
            let response = try ResponseInfo.parse(from: data["response"] as? [String: Any] ?? [:])
            return .responseDone(response: response)

        case "response.output_item.added":
            let responseId = data["response_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let item = try ConversationItemInfo.parse(from: data["item"] as? [String: Any] ?? [:])
            return .responseOutputItemAdded(responseId: responseId, outputIndex: outputIndex, item: item)

        case "response.output_item.done":
            let responseId = data["response_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let item = try ConversationItemInfo.parse(from: data["item"] as? [String: Any] ?? [:])
            return .responseOutputItemDone(responseId: responseId, outputIndex: outputIndex, item: item)

        case "response.content_part.added":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let contentIndex = data["content_index"] as? Int ?? 0
            let part = try ContentPart.parse(from: data["part"] as? [String: Any] ?? [:])
            return .responseContentPartAdded(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                part: part
            )

        // Audio Response
        case "response.audio.delta":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let contentIndex = data["content_index"] as? Int ?? 0
            let delta = data["delta"] as? String ?? ""
            return .responseAudioDelta(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                delta: delta
            )

        case "response.audio_transcript.delta":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let contentIndex = data["content_index"] as? Int ?? 0
            let delta = data["delta"] as? String ?? ""
            return .responseAudioTranscriptDelta(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                delta: delta
            )

        // SOLVE-5: GA API uses different event name for model audio transcripts
        case "response.output_audio_transcript.delta":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let contentIndex = data["content_index"] as? Int ?? 0
            let delta = data["delta"] as? String ?? ""
            return .responseAudioTranscriptDelta(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                delta: delta
            )

        case "response.audio.done":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let contentIndex = data["content_index"] as? Int ?? 0
            return .responseAudioDone(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                contentIndex: contentIndex
            )

        // Text Response
        case "response.text.delta":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let contentIndex = data["content_index"] as? Int ?? 0
            let delta = data["delta"] as? String ?? ""
            return .responseTextDelta(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                delta: delta
            )

        case "response.text.done":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let contentIndex = data["content_index"] as? Int ?? 0
            let text = data["text"] as? String ?? ""
            return .responseTextDone(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                contentIndex: contentIndex,
                text: text
            )

        // Function Calls
        case "response.function_call_arguments.delta":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let callId = data["call_id"] as? String ?? ""
            let delta = data["delta"] as? String ?? ""
            return .responseFunctionCallArgumentsDelta(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                callId: callId,
                delta: delta
            )

        case "response.function_call_arguments.done":
            let responseId = data["response_id"] as? String ?? ""
            let itemId = data["item_id"] as? String ?? ""
            let outputIndex = data["output_index"] as? Int ?? 0
            let callId = data["call_id"] as? String ?? ""
            let name = data["name"] as? String ?? ""
            let arguments = data["arguments"] as? String ?? ""
            return .responseFunctionCallArgumentsDone(
                responseId: responseId,
                itemId: itemId,
                outputIndex: outputIndex,
                callId: callId,
                name: name,
                arguments: arguments
            )

        // Rate Limits
        case "rate_limits.updated":
            let rateLimits = (data["rate_limits"] as? [[String: Any]] ?? []).compactMap {
                try? RateLimitInfo.parse(from: $0)
            }
            return .rateLimitsUpdated(rateLimits: rateLimits)

        default:
            let sendableData = try SendableJSON.from(dictionary: data)
            return .unknown(type: type, data: sendableData)
        }
    }

    // MARK: - Type Name

    /// The event type name
    public var typeName: String {
        switch self {
        case .error: return "error"
        case .sessionCreated: return "session.created"
        case .sessionUpdated: return "session.updated"
        case .conversationCreated: return "conversation.created"
        case .conversationItemCreated: return "conversation.item.created"
        case .inputAudioBufferCommitted: return "input_audio_buffer.committed"
        case .inputAudioBufferSpeechStarted: return "input_audio_buffer.speech_started"
        case .inputAudioBufferSpeechStopped: return "input_audio_buffer.speech_stopped"
        case .conversationItemInputAudioTranscriptionCompleted: return "conversation.item.input_audio_transcription.completed"
        case .conversationItemInputAudioTranscriptionFailed: return "conversation.item.input_audio_transcription.failed"
        case .conversationItemTruncated: return "conversation.item.truncated"
        case .conversationItemDeleted: return "conversation.item.deleted"
        case .responseCreated: return "response.created"
        case .responseDone: return "response.done"
        case .responseOutputItemAdded: return "response.output_item.added"
        case .responseOutputItemDone: return "response.output_item.done"
        case .responseContentPartAdded: return "response.content_part.added"
        case .responseAudioDelta: return "response.audio.delta"
        case .responseAudioTranscriptDelta: return "response.audio_transcript.delta"
        case .responseAudioDone: return "response.audio.done"
        case .responseTextDelta: return "response.text.delta"
        case .responseTextDone: return "response.text.done"
        case .responseFunctionCallArgumentsDelta: return "response.function_call_arguments.delta"
        case .responseFunctionCallArgumentsDone: return "response.function_call_arguments.done"
        case .responseOutputItemDoneWithFunctionCall: return "response.output_item.done"
        case .rateLimitsUpdated: return "rate_limits.updated"
        case .unknown(let type, _): return type
        }
    }
}

// Note: Supporting types are defined in separate files:
// - SessionInfo.swift
// - ConversationInfo.swift
// - ConversationItemInfo.swift
// - ResponseInfo.swift
// - ContentPart.swift
// - ErrorInfo.swift
// - RateLimitInfo.swift
