// WebRTCTransport.swift
// Echo - Network Layer
// WebRTC implementation of RealtimeTransportProtocol

import Foundation

#if canImport(AmazonChimeSDKMedia)
import AmazonChimeSDKMedia
#endif

/// WebRTC-based transport for the Realtime API
///
/// This transport uses WebRTC peer connections for audio handling, providing:
/// - Native audio tracks (no base64 encoding)
/// - Lower latency over unreliable networks
/// - Built-in echo cancellation via WebRTC
///
/// The connection flow:
/// 1. Fetch ephemeral key using API key (transparent to developer)
/// 2. Create RTCPeerConnection
/// 3. Add local audio track (microphone)
/// 4. Create SDP offer
/// 5. Exchange SDP with OpenAI
/// 6. Set remote SDP answer
/// 7. Wait for data channel to open
/// 8. Events flow through data channel (same format as WebSocket)
public actor WebRTCTransport: RealtimeTransportProtocol {
    // MARK: - Properties
    
    private let sessionManager: WebRTCSessionManager
    private let audioHandler: WebRTCAudioHandler
    
    private var _isConnected: Bool = false
    private var isIntentionalDisconnect: Bool = false
    
    // WebRTC components (using Any to avoid compile-time dependency)
    private var peerConnection: Any?
    private var dataChannel: Any?
    private var localAudioTrack: Any?
    
    /// Stream of received JSON events from the data channel
    public let eventStream: AsyncStream<String>
    private let eventContinuation: AsyncStream<String>.Continuation
    
    /// Stream of connection state changes
    public let connectionStateStream: AsyncStream<Bool>
    private let connectionStateContinuation: AsyncStream<Bool>.Continuation
    
    // MARK: - RealtimeTransportProtocol Properties
    
    /// WebRTC transport handles audio natively through media tracks
    public var handlesAudioNatively: Bool { true }
    
    /// Whether the transport is currently connected
    public var isConnected: Bool { _isConnected }
    
    // MARK: - Initialization
    
    public init() {
        self.sessionManager = WebRTCSessionManager()
        self.audioHandler = WebRTCAudioHandler()
        
        var eventCont: AsyncStream<String>.Continuation?
        self.eventStream = AsyncStream { continuation in
            eventCont = continuation
        }
        self.eventContinuation = eventCont!
        
        var connectionCont: AsyncStream<Bool>.Continuation?
        self.connectionStateStream = AsyncStream { continuation in
            connectionCont = continuation
        }
        self.connectionStateContinuation = connectionCont!
    }
    
    // MARK: - RealtimeTransportProtocol Methods
    
    /// Connects to the Realtime API via WebRTC
    ///
    /// This method handles the entire WebRTC handshake:
    /// 1. Fetches ephemeral key (invisible to developer)
    /// 2. Creates peer connection
    /// 3. Sets up audio tracks
    /// 4. Exchanges SDP with OpenAI
    /// 5. Waits for connection
    ///
    /// - Parameters:
    ///   - apiKey: The OpenAI API key
    ///   - model: The model identifier (e.g., "gpt-realtime")
    ///   - sessionConfigJSON: Optional session configuration as JSON string
    /// - Throws: RealtimeTransportError if connection fails
    public func connect(apiKey: String, model: String, sessionConfigJSON: String?) async throws {
        print("[WebRTCTransport] 🔌 Connecting to Realtime API with WebRTC...")
        
        guard !_isConnected else {
            throw RealtimeTransportError.alreadyConnected
        }
        
        do {
            // Step 1: Configure audio session
            try await audioHandler.configureAudioSession()
            
            // Step 2: Parse session configuration from JSON
            var sessionConfig: [String: Any]? = nil
            if let configJSON = sessionConfigJSON,
               let jsonData = configJSON.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                sessionConfig = parsed
            }
            
            // Step 3: Build session configuration
            let config = WebRTCSessionManager.SessionConfiguration(
                model: model,
                voice: sessionConfig?["voice"] as? String,
                instructions: sessionConfig?["instructions"] as? String,
                turnDetection: sessionConfig?["turn_detection"] as? [String: Any],
                tools: sessionConfig?["tools"] as? [[String: Any]]
            )
            
            // Step 3: Fetch ephemeral key (invisible to developer)
            let ephemeralKey = try await sessionManager.fetchEphemeralKey(
                apiKey: apiKey,
                configuration: config
            )
            
            // Step 4: Create WebRTC peer connection and exchange SDP
            try await setupWebRTCConnection(ephemeralKey: ephemeralKey)
            
            _isConnected = true
            connectionStateContinuation.yield(true)
            print("[WebRTCTransport] ✅ WebRTC connection established")
            
        } catch {
            await cleanup()
            throw RealtimeTransportError.connectionFailed(error)
        }
    }
    
    /// Disconnects from the WebRTC connection gracefully
    public func disconnect() async {
        guard _isConnected else { return }
        
        print("[WebRTCTransport] 🔌 Disconnecting WebRTC...")
        
        isIntentionalDisconnect = true
        await cleanup()
        connectionStateContinuation.yield(false)
        
        print("[WebRTCTransport] ✅ Disconnected cleanly")
    }
    
    /// Sends a client event as JSON via the data channel
    ///
    /// - Parameter eventJSON: The JSON string representation of the client event
    /// - Throws: RealtimeTransportError if sending fails
    public func send(eventJSON: String) async throws {
        guard _isConnected else {
            throw RealtimeTransportError.notConnected
        }
        
        // Send via data channel
        // Note: Actual implementation depends on WebRTC framework
        try await sendViaDataChannel(eventJSON)
    }
    
    /// WebRTC handles audio natively - this throws an error
    ///
    /// - Parameter base64Audio: Base64-encoded audio (not used)
    /// - Throws: RealtimeTransportError.unsupportedOperation
    public func sendAudio(_ base64Audio: String) async throws {
        throw RealtimeTransportError.unsupportedOperation(
            "WebRTC transport handles audio natively through media tracks"
        )
    }
    
    /// Sets up the local audio input (microphone)
    public func setupLocalAudio() async throws {
        // Configure audio session if not already done
        let isReady = await audioHandler.isReady
        if !isReady {
            try await audioHandler.configureAudioSession()
        }
        
        // Note: Actual audio track setup depends on WebRTC framework
        print("[WebRTCTransport] 🎤 Local audio setup complete")
    }
    
    /// Mutes or unmutes the local audio input
    ///
    /// - Parameter muted: Whether to mute the audio
    public func setLocalAudioMuted(_ muted: Bool) async {
        await audioHandler.setMuted(muted)
        
        // Note: Also need to enable/disable the WebRTC audio track
        // This depends on the WebRTC framework being used
    }
    
    // MARK: - WebRTC Setup
    
    /// Sets up the WebRTC peer connection and exchanges SDP
    private func setupWebRTCConnection(ephemeralKey: String) async throws {
        print("[WebRTCTransport] 📡 Setting up WebRTC peer connection...")
        
        #if canImport(AmazonChimeSDKMedia)
        // Full WebRTC implementation when framework is available
        try await setupPeerConnectionWithFramework(ephemeralKey: ephemeralKey)
        #else
        // Placeholder implementation for when WebRTC framework is not available
        // This allows the code to compile but will throw at runtime
        throw RealtimeTransportError.connectionFailed(
            NSError(domain: "WebRTCTransport", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "WebRTC framework not available. Please ensure the WebRTC dependency is properly configured."
            ])
        )
        #endif
    }
    
    #if canImport(AmazonChimeSDKMedia)
    /// Full WebRTC implementation with the Amazon Chime SDK
    private func setupPeerConnectionWithFramework(ephemeralKey: String) async throws {
        // This would contain the full WebRTC implementation
        // For now, we'll use a placeholder that demonstrates the flow
        
        // 1. Create peer connection configuration
        // 2. Create peer connection
        // 3. Create data channel named "oai-events"
        // 4. Add local audio track
        // 5. Create SDP offer
        // 6. Exchange SDP with OpenAI
        // 7. Set remote description
        // 8. Wait for ICE connection
        
        print("[WebRTCTransport] 🔧 WebRTC framework detected, setting up connection...")
        
        // TODO: Implement full WebRTC connection using the framework
        // This requires the specific WebRTC API calls for:
        // - RTCPeerConnection creation
        // - RTCDataChannel creation
        // - Audio track management
        // - SDP offer/answer exchange
        
        throw RealtimeTransportError.connectionFailed(
            NSError(domain: "WebRTCTransport", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "WebRTC implementation in progress"
            ])
        )
    }
    #endif
    
    /// Sends data via the WebRTC data channel
    private func sendViaDataChannel(_ message: String) async throws {
        // Note: Actual implementation depends on WebRTC framework
        // The data channel send would look like:
        // dataChannel?.sendData(message.data(using: .utf8)!)
        
        guard dataChannel != nil else {
            throw RealtimeTransportError.dataChannelFailed("Data channel not available")
        }
        
        // Placeholder - actual send would go here
        print("[WebRTCTransport] 📤 Sending via data channel: \(message.prefix(100))...")
    }
    
    /// Handles incoming data channel messages
    private func handleDataChannelMessage(_ message: String) {
        eventContinuation.yield(message)
    }
    
    // MARK: - Cleanup
    
    private func cleanup() async {
        _isConnected = false
        isIntentionalDisconnect = false
        
        // Close data channel
        dataChannel = nil
        
        // Close peer connection
        peerConnection = nil
        
        // Remove audio track
        localAudioTrack = nil
        
        // Deactivate audio session
        await audioHandler.deactivateAudioSession()
        
        // Clear ephemeral key
        await sessionManager.clearEphemeralKey()
    }
    
    deinit {
        eventContinuation.finish()
        connectionStateContinuation.finish()
    }
}

