// InternalDelegates.swift
// Echo - Internal Protocols
// Delegate protocols for internal coordination between components

import Foundation

// MARK: - RealtimeClient Delegate

/// Delegate protocol for RealtimeClient internal events
/// Used for direct method calls instead of event-based coordination
public protocol RealtimeClientDelegate: AnyObject, Sendable {
    /// Called when a tool call is received from the server
    /// - Parameters:
    ///   - client: The RealtimeClient that received the tool call
    ///   - call: The tool call details
    func realtimeClient(_ client: RealtimeClient, didReceiveToolCall call: ToolCall) async
    
    /// Called when the user starts speaking (VAD detected speech start)
    /// - Parameter client: The RealtimeClient that detected speech
    func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async
    
    /// Called when the user stops speaking (VAD detected silence)
    /// - Parameter client: The RealtimeClient that detected silence
    func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async
    
    /// Called when user transcription is completed
    /// - Parameters:
    ///   - client: The RealtimeClient that received the transcription
    ///   - transcript: The transcribed text
    ///   - itemId: The ID of the conversation item
    func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async
    
    /// Called when assistant response text is received
    /// - Parameters:
    ///   - client: The RealtimeClient that received the response
    ///   - text: The assistant's response text
    ///   - itemId: The ID of the conversation item
    func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async
    
    /// Called when assistant starts responding
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - itemId: The ID of the new response item
    func realtimeClient(_ client: RealtimeClient, didStartAssistantResponse itemId: String) async
    
    /// Called when user audio buffer is committed
    /// - Parameters:
    ///   - client: The RealtimeClient
    ///   - itemId: The ID of the committed audio item
    func realtimeClient(_ client: RealtimeClient, didCommitUserAudio itemId: String) async
}

// MARK: - TurnManager Delegate

/// Delegate protocol for TurnManager internal events
/// Used for direct method calls to request interruptions
public protocol TurnManagerDelegate: AnyObject, Sendable {
    /// Called when turn manager requests interruption of assistant
    /// - Parameter manager: The TurnManager requesting interruption
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
public protocol ToolExecuting: AnyObject, Sendable {
    /// Executes a tool call and returns the result
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool execution result
    func execute(toolCall: ToolCall) async -> ToolResult
}

// MARK: - Tool Handler Provider

/// Protocol for components that provide custom tool handlers
public protocol ToolHandlerProvider: AnyObject {
    /// Optional custom tool handler. If set, overrides automatic tool execution.
    var toolHandler: (@Sendable (ToolCall) async throws -> String)? { get }
}

// MARK: - Default Implementations

/// Default implementation for optional delegate methods
public extension RealtimeClientDelegate {
    func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async {}
    func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async {}
}

public extension TurnManagerDelegate {
    func turnManagerDidRequestInterruption(_ manager: TurnManager) async {}
}

