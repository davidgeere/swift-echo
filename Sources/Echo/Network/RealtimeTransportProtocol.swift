// RealtimeTransportProtocol.swift
// Echo - Network Layer
// Protocol abstraction for Realtime API transport (WebSocket or WebRTC)

import Foundation

/// Transport type for connecting to the Realtime API
public enum RealtimeTransportType: String, Sendable, CaseIterable {
    /// WebSocket transport - sends audio as base64-encoded chunks
    case webSocket
    
    /// WebRTC transport - uses native media tracks for audio
    case webRTC
}

/// Protocol defining the interface for Realtime API transports
///
/// Both WebSocket and WebRTC transports implement this protocol, allowing
/// the RealtimeClient to use either transport interchangeably. The transport
/// handles connection establishment, event messaging, and audio routing.
///
/// Key differences between transports:
/// - **WebSocket**: Audio sent as base64 via `input_audio_buffer.append` events
/// - **WebRTC**: Audio handled natively through RTCPeerConnection media tracks
public protocol RealtimeTransportProtocol: Actor {
    // MARK: - Streams
    
    /// Stream of JSON event strings received from the server
    ///
    /// Events have the same format for both transports (WebSocket messages
    /// or RTCDataChannel messages). The caller should parse these as JSON
    /// and handle them as server events.
    var eventStream: AsyncStream<String> { get }
    
    /// Stream of connection state changes
    ///
    /// Yields `true` when connected, `false` when disconnected.
    var connectionStateStream: AsyncStream<Bool> { get }
    
    // MARK: - Connection
    
    /// Connects to the Realtime API
    ///
    /// For WebSocket: Establishes direct WebSocket connection with API key
    /// For WebRTC: Fetches ephemeral key, performs SDP exchange, establishes peer connection
    ///
    /// - Parameters:
    ///   - apiKey: The OpenAI API key
    ///   - model: The model identifier (e.g., "gpt-realtime")
    ///   - sessionConfigJSON: Optional session configuration as JSON string
    /// - Throws: Transport-specific connection errors
    func connect(apiKey: String, model: String, sessionConfigJSON: String?) async throws
    
    /// Disconnects from the Realtime API
    ///
    /// Gracefully closes the connection and cleans up resources.
    func disconnect() async
    
    /// Whether the transport is currently connected
    var isConnected: Bool { get }
    
    // MARK: - Events
    
    /// Sends a client event to the server
    ///
    /// Events are sent as JSON strings over the transport's messaging channel
    /// (WebSocket messages or RTCDataChannel).
    ///
    /// - Parameter eventJSON: The JSON string representation of the client event
    /// - Throws: If sending fails or transport is not connected
    func send(eventJSON: String) async throws
    
    // MARK: - Audio Handling
    
    /// Whether this transport handles audio natively through media tracks
    ///
    /// - `true` for WebRTC: Audio flows through RTCPeerConnection tracks
    /// - `false` for WebSocket: Audio must be sent as base64 via events
    var handlesAudioNatively: Bool { get }
    
    /// Sends base64-encoded audio to the server
    ///
    /// Only used when `handlesAudioNatively` is `false` (WebSocket transport).
    /// WebRTC transport does not use this method as audio flows through media tracks.
    ///
    /// - Parameter base64Audio: Base64-encoded PCM16 audio data
    /// - Throws: If sending fails or transport doesn't support this method
    func sendAudio(_ base64Audio: String) async throws
    
    /// Sets up the local audio input (microphone)
    ///
    /// For WebRTC: Adds local audio track to the peer connection
    /// For WebSocket: No-op (audio handled by AudioCapture)
    func setupLocalAudio() async throws
    
    /// Mutes or unmutes the local audio input
    ///
    /// For WebRTC: Enables/disables the local audio track
    /// For WebSocket: No-op (handled by AudioCapture)
    ///
    /// - Parameter muted: Whether to mute the audio
    func setLocalAudioMuted(_ muted: Bool) async
}

// MARK: - Default Implementations

public extension RealtimeTransportProtocol {
    /// Default implementation for transports that don't handle audio natively
    func setupLocalAudio() async throws {
        // No-op for WebSocket transport
    }
    
    /// Default implementation for muting
    func setLocalAudioMuted(_ muted: Bool) async {
        // No-op for WebSocket transport
    }
}

// MARK: - Transport Errors

/// Errors that can occur during transport operations
public enum RealtimeTransportError: Error, Sendable {
    /// Transport is already connected
    case alreadyConnected
    
    /// Transport is not connected
    case notConnected
    
    /// Failed to establish connection
    case connectionFailed(Error)
    
    /// Failed to fetch ephemeral key (WebRTC only)
    case ephemeralKeyFailed(Error)
    
    /// SDP exchange failed (WebRTC only)
    case sdpExchangeFailed(Error)
    
    /// Data channel failed to open (WebRTC only)
    case dataChannelFailed(String)
    
    /// Failed to send event
    case sendFailed(Error)
    
    /// Audio setup failed
    case audioSetupFailed(Error)
    
    /// Transport does not support this operation
    case unsupportedOperation(String)
}

extension RealtimeTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyConnected:
            return "Transport is already connected"
        case .notConnected:
            return "Transport is not connected"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .ephemeralKeyFailed(let error):
            return "Failed to fetch ephemeral key: \(error.localizedDescription)"
        case .sdpExchangeFailed(let error):
            return "SDP exchange failed: \(error.localizedDescription)"
        case .dataChannelFailed(let message):
            return "Data channel failed: \(message)"
        case .sendFailed(let error):
            return "Failed to send event: \(error.localizedDescription)"
        case .audioSetupFailed(let error):
            return "Audio setup failed: \(error.localizedDescription)"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        }
    }
}

