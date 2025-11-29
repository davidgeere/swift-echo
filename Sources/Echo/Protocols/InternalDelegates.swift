// InternalDelegates.swift
// Echo - Internal Coordination Protocols
// Delegate protocols for direct internal communication (no event-based coupling)

import Foundation

// MARK: - Tool Execution Protocol

/// Protocol for components that can execute tools
public protocol ToolExecuting: AnyObject, Sendable {
    /// Executes a tool call and returns the result
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool result
    func execute(toolCall: ToolCall) async -> ToolResult
}

// MARK: - Audio Interruptible Protocol

/// Protocol for components that can be interrupted (e.g., audio playback)
public protocol AudioInterruptible: AnyObject, Sendable {
    /// Interrupts the current audio operation
    func interrupt() async
}

// MARK: - RealtimeClient Delegate

/// Delegate protocol for RealtimeClient internal events
/// These are called directly instead of via EventEmitter to avoid orphaned Tasks
public protocol RealtimeClientDelegate: AnyObject, Sendable {
    /// Called when a tool call is received from the server
    /// - Parameters:
    ///   - client: The RealtimeClient that received the tool call
    ///   - call: The tool call details
    func realtimeClient(_ client: RealtimeClient, didReceiveToolCall call: ToolCall) async
    
    /// Called when user speech is detected
    /// - Parameter client: The RealtimeClient that detected speech
    func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async
    
    /// Called when user stops speaking (silence detected)
    /// - Parameter client: The RealtimeClient that detected silence
    func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async
    
    /// Called when user transcription is completed
    /// - Parameters:
    ///   - client: The RealtimeClient that received the transcription
    ///   - transcript: The transcribed text
    ///   - itemId: The conversation item ID
    func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async
    
    /// Called when the assistant starts responding
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - itemId: The assistant's response item ID
    func realtimeClient(_ client: RealtimeClient, didStartAssistantResponse itemId: String) async
    
    /// Called when assistant response text is received
    /// - Parameters:
    ///   - client: The RealtimeClient that received the response
    ///   - text: The complete response text
    ///   - itemId: The conversation item ID
    func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async
    
    /// Called when the assistant finishes responding
    /// - Parameter client: The RealtimeClient
    func realtimeClientDidFinishAssistantResponse(_ client: RealtimeClient) async
    
    /// Called when the user's audio buffer is committed
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - itemId: The committed item ID
    func realtimeClient(_ client: RealtimeClient, didCommitAudioBuffer itemId: String) async
}

// MARK: - TurnManager Delegate

/// Delegate protocol for TurnManager events
/// Called directly to request actions from the owner
public protocol TurnManagerDelegate: AnyObject, Sendable {
    /// Called when the turn manager determines the assistant should be interrupted
    /// - Parameter manager: The TurnManager requesting interruption
    func turnManagerDidRequestInterruption(_ manager: TurnManager) async
    
    /// Called when the user's turn ends (in manual mode)
    /// - Parameter manager: The TurnManager signaling turn end
    func turnManagerDidEndUserTurn(_ manager: TurnManager) async
}

// MARK: - Tool Handler Provider

/// Protocol for providing custom tool handlers
public protocol ToolHandlerProvider: AnyObject {
    /// Custom tool handler closure. If set, this is called instead of automatic execution.
    var toolHandler: ((ToolCall) async throws -> String)? { get }
}

