// InternalDelegates.swift
// Echo - Internal Protocols
// Delegate protocols for internal component coordination (no event-based Tasks)

import Foundation

// MARK: - RealtimeClient Delegate

/// Delegate protocol for RealtimeClient to notify its owner of internal events.
/// This replaces event-based coordination with direct method calls.
public protocol RealtimeClientDelegate: AnyObject, Sendable {
    /// Called when a tool call is received from the API
    /// - Parameters:
    ///   - client: The RealtimeClient that received the tool call
    ///   - call: The tool call to execute
    func realtimeClient(_ client: RealtimeClient, didReceiveToolCall call: ToolCall) async
    
    /// Called when user speech is detected (VAD speech started)
    /// - Parameter client: The RealtimeClient that detected speech
    func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async
    
    /// Called when user silence is detected (VAD speech stopped)
    /// - Parameter client: The RealtimeClient that detected silence
    func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async
    
    /// Called when a user transcription is completed
    /// - Parameters:
    ///   - client: The RealtimeClient that received the transcription
    ///   - transcript: The transcribed text
    ///   - itemId: The conversation item ID
    func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async
    
    /// Called when an assistant response is received
    /// - Parameters:
    ///   - client: The RealtimeClient that received the response
    ///   - text: The response text
    ///   - itemId: The conversation item ID
    func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async
    
    /// Called when an assistant response item is created
    /// - Parameters:
    ///   - client: The RealtimeClient that created the response
    ///   - itemId: The conversation item ID
    func realtimeClient(_ client: RealtimeClient, didCreateAssistantResponse itemId: String) async
    
    /// Called when user audio buffer is committed
    /// - Parameters:
    ///   - client: The RealtimeClient that committed the buffer
    ///   - itemId: The conversation item ID
    func realtimeClient(_ client: RealtimeClient, didCommitUserAudioBuffer itemId: String) async
    
    /// Called when the assistant starts speaking
    /// - Parameter client: The RealtimeClient
    func realtimeClientDidStartAssistantSpeaking(_ client: RealtimeClient) async
    
    /// Called when the assistant finishes speaking
    /// - Parameter client: The RealtimeClient
    func realtimeClientDidFinishAssistantSpeaking(_ client: RealtimeClient) async
}

// MARK: - TurnManager Delegate

/// Delegate protocol for TurnManager to request actions from its owner.
/// This replaces event emissions for internal coordination.
public protocol TurnManagerDelegate: AnyObject, Sendable {
    /// Called when the TurnManager requests an interruption of the assistant
    /// - Parameter manager: The TurnManager requesting the interruption
    func turnManagerDidRequestInterruption(_ manager: TurnManager) async
}

// MARK: - Audio Interruptible

/// Protocol for components that can be interrupted (e.g., audio playback)
public protocol AudioInterruptible: AnyObject, Sendable {
    /// Interrupts the current audio operation
    func interrupt() async
}

// MARK: - Tool Executing

/// Protocol for components that can execute tools
public protocol ToolExecuting: Sendable {
    /// Executes a tool call and returns the result
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool result
    func execute(toolCall: ToolCall) async -> ToolResult
}

// MARK: - Tool Handler Provider

/// Protocol for providing custom tool handlers
public protocol ToolHandlerProvider: AnyObject, Sendable {
    /// Optional custom tool handler. If set, this is called instead of automatic execution.
    var toolHandler: (@Sendable (ToolCall) async throws -> String)? { get }
}

