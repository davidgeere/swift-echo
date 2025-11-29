// EventType.swift
// Echo - Event Infrastructure
// Enum categorizing all event types for type-safe event handling

import Foundation

/// Categorizes all event types in the Echo system for type-safe filtering and registration
public enum EventType: String, Sendable, CaseIterable {
    // MARK: - User Speech Events

    /// VAD detected that the user started speaking
    case userStartedSpeaking

    /// VAD detected that the user stopped speaking
    case userStoppedSpeaking

    /// User audio buffer was committed (creates message slot)
    case userAudioBufferCommitted

    /// User speech transcript has been completed
    case userTranscriptionCompleted

    // MARK: - Assistant Response Events

    /// Assistant response was created (starts message slot)
    case assistantResponseCreated

    /// Assistant has started speaking/responding
    case assistantStartedSpeaking

    /// Assistant has stopped speaking/responding
    case assistantStoppedSpeaking

    /// Assistant response is complete (finalizes message)
    case assistantResponseDone

    /// Streaming text chunk received from assistant
    case assistantTextDelta

    /// Audio chunk received from assistant
    case assistantAudioDelta

    // MARK: - Audio Events

    /// Audio level changed (for visualizations)
    case audioLevelChanged

    /// Audio status changed (listening, speaking, processing, idle)
    case audioStatusChanged

    /// Audio system is starting (setup begins)
    case audioStarting

    /// Audio system has started (capture and playback ready)
    case audioStarted

    /// Audio system has stopped
    case audioStopped

    /// Audio output device changed
    case audioOutputChanged

    // MARK: - Turn Events

    /// Speaking turn changed between user and assistant
    case turnChanged

    /// User turn ended
    case turnEnded

    /// Assistant was interrupted
    case assistantInterrupted

    // MARK: - Tool Events

    /// Function/tool call has been requested by the model
    case toolCallRequested

    /// Tool result has been submitted back to the model
    case toolResultSubmitted
    
    /// Tool execution completed successfully
    case toolExecutionCompleted
    
    /// Tool execution failed with an error
    case toolExecutionFailed

    // MARK: - Message Events

    /// Message has been finalized and added to the conversation queue
    case messageFinalized

    // MARK: - Connection Events

    /// WebSocket or HTTP connection status changed
    case connectionStatusChanged

    // MARK: - Mode Events

    /// Mode is switching
    case modeSwitching

    /// Mode has switched
    case modeSwitched

    // MARK: - Embedding Events
    
    /// Single embedding generated
    case embeddingGenerated
    
    /// Batch embeddings generated
    case embeddingsGenerated
    
    // MARK: - Error Events

    /// An error occurred during operation
    case error
}
