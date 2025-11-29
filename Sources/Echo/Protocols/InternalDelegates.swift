// InternalDelegates.swift
// Echo - Internal Protocols
// Delegate protocols for internal coordination between components

import Foundation

// MARK: - Tool Execution

/// Protocol for components that execute tools
public protocol ToolExecuting: AnyObject, Sendable {
    /// Executes a tool call and returns the result
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool result
    func execute(toolCall: ToolCall) async -> ToolResult
}

/// Protocol for providing custom tool handlers
public protocol ToolHandlerProvider: AnyObject {
    /// Optional custom tool handler. If nil, tools execute automatically.
    /// If set, this is called instead of automatic execution.
    var toolHandler: (@Sendable (ToolCall) async throws -> String)? { get }
}

// MARK: - RealtimeClient Delegate

/// Delegate protocol for RealtimeClient internal events
/// Used by Conversation to receive updates without spawning listener Tasks
public protocol RealtimeClientDelegate: AnyObject, Sendable {
    /// Called when a tool call is received from the model
    /// - Parameters:
    ///   - client: The RealtimeClient that received the tool call
    ///   - call: The tool call to execute
    func realtimeClient(_ client: RealtimeClient, didReceiveToolCall call: ToolCall) async
    
    /// Called when user speech is detected
    /// - Parameter client: The RealtimeClient that detected speech
    func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async
    
    /// Called when user silence is detected
    /// - Parameter client: The RealtimeClient that detected silence
    func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async
    
    /// Called when a user transcript is completed
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - transcript: The completed transcript text
    ///   - itemId: The ID of the conversation item
    func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async
    
    /// Called when an assistant response is started
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - itemId: The ID of the response item
    func realtimeClient(_ client: RealtimeClient, didStartAssistantResponse itemId: String) async
    
    /// Called when an assistant response is completed
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - text: The complete response text
    ///   - itemId: The ID of the response item
    func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async
    
    /// Called when user audio buffer is committed
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - itemId: The ID of the committed item
    func realtimeClient(_ client: RealtimeClient, didCommitAudioBuffer itemId: String) async
}

// MARK: - TurnManager Delegate

/// Delegate protocol for TurnManager events
/// Used to notify owner when turn-related actions are needed
public protocol TurnManagerDelegate: AnyObject, Sendable {
    /// Called when the TurnManager requests an interruption of the assistant
    /// - Parameter manager: The TurnManager requesting interruption
    func turnManagerDidRequestInterruption(_ manager: TurnManager) async
}

// MARK: - Audio Interruptible

/// Protocol for components that can be interrupted
public protocol AudioInterruptible: AnyObject, Sendable {
    /// Interrupts the current operation
    func interrupt() async
}

