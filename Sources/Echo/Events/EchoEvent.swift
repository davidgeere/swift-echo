// EchoEvent.swift
// Echo - Event Infrastructure
// Complete event definitions with associated data for the event-driven API

import Foundation

/// Represents all events that can be emitted by the Echo system.
/// Each event carries its specific payload as associated values.
public enum EchoEvent: Sendable {
    // MARK: - User Speech Events

    /// VAD detected that the user started speaking
    case userStartedSpeaking

    /// VAD detected that the user stopped speaking
    case userStoppedSpeaking

    /// User audio buffer was committed (creates message slot)
    /// - Parameter itemId: The conversation item ID assigned by the API
    case userAudioBufferCommitted(itemId: String)

    /// User speech transcript has been completed
    /// - Parameters:
    ///   - transcript: The completed transcript text
    ///   - itemId: The conversation item ID for this transcript
    case userTranscriptionCompleted(transcript: String, itemId: String)

    // MARK: - Assistant Response Events

    /// Assistant response was created (starts message slot)
    /// - Parameter itemId: The response item ID
    case assistantResponseCreated(itemId: String)

    /// Assistant has started speaking/responding
    case assistantStartedSpeaking

    /// Assistant has stopped speaking/responding
    case assistantStoppedSpeaking

    /// Assistant response is complete (finalizes message)
    /// - Parameters:
    ///   - itemId: The response item ID
    ///   - text: The complete response text
    case assistantResponseDone(itemId: String, text: String)

    /// Streaming text chunk received from assistant
    /// - Parameter delta: The incremental text chunk
    case assistantTextDelta(delta: String)

    /// Audio chunk received from assistant
    /// - Parameter audioChunk: The audio data chunk
    case assistantAudioDelta(audioChunk: Data)

    // MARK: - Audio Events

    /// Audio level changed (for visualizations)
    /// - Parameter level: Audio level from 0.0 (silent) to 1.0 (loudest)
    case audioLevelChanged(level: Double)

    /// Audio status changed
    /// - Parameter status: The new audio status
    case audioStatusChanged(status: AudioStatus)

    /// Audio system is starting (setup begins)
    case audioStarting

    /// Audio system has started (capture and playback ready)
    case audioStarted

    /// Audio system has stopped
    case audioStopped

    /// Audio output device changed
    /// - Parameter device: The new audio output device
    case audioOutputChanged(device: AudioOutputDeviceType)

    // MARK: - Turn Events

    /// Speaking turn changed between user and assistant
    /// - Parameter speaker: The current speaker (user, assistant, or none)
    case turnChanged(speaker: TurnManager.Speaker)

    /// User turn ended
    case turnEnded

    /// Assistant was interrupted
    case assistantInterrupted

    // MARK: - Tool Events

    /// Function/tool call has been requested by the model
    /// - Parameter toolCall: The tool call details
    case toolCallRequested(toolCall: ToolCall)

    /// Tool result has been submitted back to the model
    /// - Parameters:
    ///   - toolCallId: The ID of the tool call this result is for
    ///   - result: The tool execution result
    case toolResultSubmitted(toolCallId: String, result: String)

    // MARK: - Message Events

    /// Message has been finalized and added to the conversation queue
    /// - Parameter message: The finalized message
    case messageFinalized(message: Message)

    // MARK: - Connection Events

    /// WebSocket or HTTP connection status changed
    /// - Parameter isConnected: Whether the connection is currently active
    case connectionStatusChanged(isConnected: Bool)

    // MARK: - Mode Events

    /// Mode is switching
    /// - Parameters:
    ///   - from: The mode switching from
    ///   - to: The mode switching to
    case modeSwitching(from: EchoMode, to: EchoMode)

    /// Mode has switched
    /// - Parameter to: The new mode
    case modeSwitched(to: EchoMode)

    // MARK: - Embedding Events
    
    /// Single embedding generated
    /// - Parameters:
    ///   - text: The text that was embedded
    ///   - dimensions: The dimension count of the embedding
    ///   - model: The model used
    case embeddingGenerated(text: String, dimensions: Int, model: String)
    
    /// Batch embeddings generated
    /// - Parameters:
    ///   - count: Number of embeddings generated
    ///   - dimensions: The dimension count of the embeddings
    ///   - model: The model used
    case embeddingsGenerated(count: Int, dimensions: Int, model: String)
    
    // MARK: - Error Events

    /// An error occurred during operation
    /// - Parameter error: The error that occurred
    case error(error: Error)

    // MARK: - Helper Properties

    /// Returns the EventType for this event (for filtering and registration)
    public var type: EventType {
        switch self {
        case .userStartedSpeaking:
            return .userStartedSpeaking
        case .userStoppedSpeaking:
            return .userStoppedSpeaking
        case .userAudioBufferCommitted:
            return .userAudioBufferCommitted
        case .userTranscriptionCompleted:
            return .userTranscriptionCompleted
        case .assistantResponseCreated:
            return .assistantResponseCreated
        case .assistantStartedSpeaking:
            return .assistantStartedSpeaking
        case .assistantStoppedSpeaking:
            return .assistantStoppedSpeaking
        case .assistantResponseDone:
            return .assistantResponseDone
        case .assistantTextDelta:
            return .assistantTextDelta
        case .assistantAudioDelta:
            return .assistantAudioDelta
        case .audioLevelChanged:
            return .audioLevelChanged
        case .audioStatusChanged:
            return .audioStatusChanged
        case .audioStarting:
            return .audioStarting
        case .audioStarted:
            return .audioStarted
        case .audioStopped:
            return .audioStopped
        case .audioOutputChanged:
            return .audioOutputChanged
        case .turnChanged:
            return .turnChanged
        case .turnEnded:
            return .turnEnded
        case .assistantInterrupted:
            return .assistantInterrupted
        case .toolCallRequested:
            return .toolCallRequested
        case .toolResultSubmitted:
            return .toolResultSubmitted
        case .messageFinalized:
            return .messageFinalized
        case .connectionStatusChanged:
            return .connectionStatusChanged
        case .modeSwitching:
            return .modeSwitching
        case .modeSwitched:
            return .modeSwitched
        case .embeddingGenerated:
            return .embeddingGenerated
        case .embeddingsGenerated:
            return .embeddingsGenerated
        case .error:
            return .error
        }
    }
}

// Note: AudioStatus is defined in Audio/AudioStatus.swift
// Note: Speaker is defined in Core/Speaker.swift
// Note: Message type is defined in Core/Message.swift
// Note: ToolCall is defined in Tools/ToolCall.swift
