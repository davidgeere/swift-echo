// WebRTCTransport.swift
// Echo - Network Layer
// WebRTC implementation of RealtimeTransportProtocol

import Foundation
@preconcurrency import WebRTC

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
    public let audioHandler: WebRTCAudioHandler
    
    private var _isConnected: Bool = false
    private var isIntentionalDisconnect: Bool = false
    
    // WebRTC components
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var remoteAudioTrack: RTCAudioTrack?
    private var audioSource: RTCAudioSource?
    
    // Delegate wrapper to handle WebRTC callbacks
    private var peerConnectionDelegate: PeerConnectionDelegate?
    private var dataChannelDelegate: DataChannelDelegate?
    
    // Audio level monitoring for WebRTC
    private var audioLevelMonitorTask: Task<Void, Never>?
    
    /// Stream of output audio levels for visualization
    public let outputLevelStream: AsyncStream<AudioLevels>
    private let outputLevelContinuation: AsyncStream<AudioLevels>.Continuation
    
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
        
        var outputLevelCont: AsyncStream<AudioLevels>.Continuation?
        self.outputLevelStream = AsyncStream { continuation in
            outputLevelCont = continuation
        }
        self.outputLevelContinuation = outputLevelCont!
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
            // SOLVE-4: Include transcription configuration for WebRTC
            let config = WebRTCSessionManager.SessionConfiguration(
                model: model,
                voice: sessionConfig?["voice"] as? String,
                instructions: sessionConfig?["instructions"] as? String,
                turnDetection: sessionConfig?["turn_detection"] as? [String: Any],
                tools: sessionConfig?["tools"] as? [[String: Any]],
                transcription: sessionConfig?["transcription"] as? [String: Any]
            )
            
            // Step 4: Fetch ephemeral key (invisible to developer)
            let ephemeralKey = try await sessionManager.fetchEphemeralKey(
                apiKey: apiKey,
                configuration: config
            )
            
            // Step 5: Create WebRTC peer connection and exchange SDP
            try await setupWebRTCConnection(ephemeralKey: ephemeralKey, model: model)
            
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
        
        guard let dataChannel = dataChannel else {
            throw RealtimeTransportError.dataChannelFailed("Data channel not available")
        }
        
        guard let data = eventJSON.data(using: .utf8) else {
            throw RealtimeTransportError.dataChannelFailed("Failed to encode message")
        }
        
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        let sent = dataChannel.sendData(buffer)
        
        if !sent {
            throw RealtimeTransportError.dataChannelFailed("Failed to send data")
        }
        
        print("[WebRTCTransport] 📤 Sent: \(eventJSON.prefix(100))...")
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
        
        // Enable the audio track
        localAudioTrack?.isEnabled = true
        print("[WebRTCTransport] 🎤 Local audio setup complete")
    }
    
    /// Mutes or unmutes the local audio input
    ///
    /// - Parameter muted: Whether to mute the audio
    public func setLocalAudioMuted(_ muted: Bool) async {
        await audioHandler.setMuted(muted)
        localAudioTrack?.isEnabled = !muted
    }
    
    // MARK: - WebRTC Setup
    
    /// Sets up the WebRTC peer connection and exchanges SDP
    private func setupWebRTCConnection(ephemeralKey: String, model: String) async throws {
        print("[WebRTCTransport] 📡 Setting up WebRTC peer connection...")
        
        // Initialize WebRTC factory
        RTCInitializeSSL()
        
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
        
        guard let factory = peerConnectionFactory else {
            throw RealtimeTransportError.connectionFailed(
                NSError(domain: "WebRTCTransport", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create peer connection factory"
                ])
            )
        }
        
        // Create peer connection configuration
        let rtcConfig = RTCConfiguration()
        rtcConfig.iceServers = [] // OpenAI handles ICE internally
        rtcConfig.sdpSemantics = .unifiedPlan
        rtcConfig.continualGatheringPolicy = .gatherContinually
        rtcConfig.bundlePolicy = .maxBundle
        rtcConfig.rtcpMuxPolicy = .require
        
        // Create constraints
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        
        // Create peer connection delegate
        let pcDelegate = PeerConnectionDelegate()
        self.peerConnectionDelegate = pcDelegate
        
        // Setup delegate callbacks
        pcDelegate.onConnectionStateChange = { [weak self] state in
            Task { [weak self] in
                await self?.handleConnectionStateChange(state)
            }
        }
        pcDelegate.onIceConnectionStateChange = { [weak self] state in
            Task { [weak self] in
                await self?.handleIceConnectionStateChange(state)
            }
        }
        pcDelegate.onRemoteAudioTrack = { [weak self] track in
            Task { [weak self] in
                await self?.handleRemoteAudioTrack(track)
            }
        }
        
        // Create peer connection
        guard let pc = factory.peerConnection(
            with: rtcConfig,
            constraints: constraints,
            delegate: pcDelegate
        ) else {
            throw RealtimeTransportError.connectionFailed(
                NSError(domain: "WebRTCTransport", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create peer connection"
                ])
            )
        }
        self.peerConnection = pc
        
        // Create and configure data channel for events
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        
        guard let dc = pc.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig) else {
            throw RealtimeTransportError.dataChannelFailed("Failed to create data channel")
        }
        
        let dcDelegate = DataChannelDelegate()
        dcDelegate.onMessage = { [weak self] message in
            Task { [weak self] in
                await self?.handleDataChannelMessage(message)
            }
        }
        dcDelegate.onStateChange = { [weak self] state in
            Task { [weak self] in
                await self?.handleDataChannelStateChange(state)
            }
        }
        dc.delegate = dcDelegate
        self.dataChannel = dc
        self.dataChannelDelegate = dcDelegate
        
        // Create audio track
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": "true",
                "googAutoGainControl": "true",
                "googNoiseSuppression": "true",
                "googHighpassFilter": "true"
            ]
        )
        
        let audioSource = factory.audioSource(with: audioConstraints)
        self.audioSource = audioSource
        
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.isEnabled = true
        self.localAudioTrack = audioTrack
        
        // Add audio track to peer connection
        let streamIds = ["stream0"]
        pc.add(audioTrack, streamIds: streamIds)
        
        // Add transceiver for receiving audio
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .sendRecv
        transceiverInit.streamIds = streamIds
        
        pc.addTransceiver(of: .audio, init: transceiverInit)
        
        // Create SDP offer
        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )
        
        // Get SDP offer string (extracting just the string to avoid Sendable issues)
        let offerSDPString = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            pc.offer(for: offerConstraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    // Extract just the SDP string which is Sendable
                    continuation.resume(returning: sdp.sdp)
                } else {
                    continuation.resume(throwing: NSError(domain: "WebRTCTransport", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "No SDP offer generated"
                    ]))
                }
            }
        }
        
        // Create the offer description and set local description
        let offer = RTCSessionDescription(type: .offer, sdp: offerSDPString)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        
        print("[WebRTCTransport] 📝 Created SDP offer, exchanging with OpenAI...")
        
        // Exchange SDP with OpenAI
        let sdpAnswer = try await sessionManager.exchangeSDP(
            sdpOffer: offerSDPString,
            ephemeralKey: ephemeralKey
        )
        
        // Set remote description
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: sdpAnswer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(remoteDescription) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        
        print("[WebRTCTransport] ✅ SDP exchange complete, connection established")
    }
    
    // MARK: - Event Handlers
    
    private func handleConnectionStateChange(_ state: RTCPeerConnectionState) {
        print("[WebRTCTransport] 🔗 Connection state: \(state.rawValue)")
        
        switch state {
        case .connected:
            _isConnected = true
            connectionStateContinuation.yield(true)
        case .disconnected, .failed, .closed:
            if !isIntentionalDisconnect {
                _isConnected = false
                connectionStateContinuation.yield(false)
            }
        default:
            break
        }
    }
    
    private func handleIceConnectionStateChange(_ state: RTCIceConnectionState) {
        print("[WebRTCTransport] 🧊 ICE state: \(state.rawValue)")
    }
    
    private func handleRemoteAudioTrack(_ track: RTCAudioTrack) {
        print("[WebRTCTransport] 🔊 Remote audio track received, starting level monitoring")
        self.remoteAudioTrack = track
        
        // Start polling WebRTC stats for audio levels
        startAudioLevelMonitoring()
    }
    
    /// Starts polling WebRTC statistics for remote audio levels
    private func startAudioLevelMonitoring() {
        // Cancel any existing task
        audioLevelMonitorTask?.cancel()
        
        // Capture peer connection reference for the task
        guard let pc = self.peerConnection else { return }
        let continuation = self.outputLevelContinuation
        
        audioLevelMonitorTask = Task { @MainActor in
            // Track previous audio level for smoothing
            var previousLevel: Float = 0
            let smoothingFactor: Float = 0.3
            
            while !Task.isCancelled {
                // Poll every ~50ms (20 times per second for smooth visualization)
                try? await Task.sleep(nanoseconds: 50_000_000)
                
                // Get stats from peer connection
                let stats = await withCheckedContinuation { (cont: CheckedContinuation<RTCStatisticsReport?, Never>) in
                    pc.statistics { report in
                        cont.resume(returning: report)
                    }
                }
                
                guard let stats = stats else { continue }
                
                // Find inbound-rtp stats for audio
                var audioLevel: Float = 0
                for (_, stat) in stats.statistics {
                    // Look for inbound audio track stats
                    if let type = stat.values["type"] as? String,
                       type == "inbound-rtp",
                       let kind = stat.values["kind"] as? String,
                       kind == "audio" {
                        
                        // Try to get audio level (0.0-1.0)
                        if let level = stat.values["audioLevel"] as? Double {
                            audioLevel = Float(level)
                            print("[DEBUG-LEVELS] 🔊 WebRTC stats audioLevel: \(audioLevel)")
                        }
                        // Alternative: get total audio energy and calculate level
                        else if let totalEnergy = stat.values["totalAudioEnergy"] as? Double,
                                let totalDuration = stat.values["totalSamplesDuration"] as? Double,
                                totalDuration > 0 {
                            // RMS level approximation from energy
                            let avgEnergy = totalEnergy / totalDuration
                            audioLevel = Float(sqrt(avgEnergy))
                            print("[DEBUG-LEVELS] 🔊 WebRTC stats calculated level: \(audioLevel)")
                        }
                        break
                    }
                }
                
                // Apply smoothing
                let smoothedLevel = previousLevel + smoothingFactor * (audioLevel - previousLevel)
                previousLevel = smoothedLevel
                
                // Create AudioLevels and emit
                // For now, we'll put all energy in the mid band (voice frequencies)
                let levels = AudioLevels(
                    level: smoothedLevel,
                    low: smoothedLevel * 0.2,
                    mid: smoothedLevel * 0.7,
                    high: smoothedLevel * 0.1
                )
                
                // Only emit if there's meaningful audio
                if smoothedLevel > 0.001 || previousLevel > 0.001 {
                    continuation.yield(levels)
                }
            }
        }
    }
    
    private func handleDataChannelMessage(_ message: String) {
        eventContinuation.yield(message)
    }
    
    private func handleDataChannelStateChange(_ state: RTCDataChannelState) {
        print("[WebRTCTransport] 📡 Data channel state: \(state.rawValue)")
        
        if state == .open {
            print("[WebRTCTransport] ✅ Data channel opened")
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() async {
        _isConnected = false
        isIntentionalDisconnect = false
        
        // Cancel audio level monitoring
        audioLevelMonitorTask?.cancel()
        audioLevelMonitorTask = nil
        
        // Close data channel
        dataChannel?.close()
        dataChannel = nil
        dataChannelDelegate = nil
        
        // Disable and remove audio tracks
        localAudioTrack?.isEnabled = false
        localAudioTrack = nil
        remoteAudioTrack = nil
        audioSource = nil
        
        // Close peer connection
        peerConnection?.close()
        peerConnection = nil
        peerConnectionDelegate = nil
        
        // Clear factory
        peerConnectionFactory = nil
        
        // Deactivate audio session
        await audioHandler.deactivateAudioSession()
        
        // Clear ephemeral key
        await sessionManager.clearEphemeralKey()
        
        RTCCleanupSSL()
    }
    
    deinit {
        eventContinuation.finish()
        connectionStateContinuation.finish()
        outputLevelContinuation.finish()
    }
}

// MARK: - Peer Connection Delegate

/// Delegate wrapper for RTCPeerConnection callbacks
private final class PeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    var onConnectionStateChange: ((RTCPeerConnectionState) -> Void)?
    var onIceConnectionStateChange: ((RTCIceConnectionState) -> Void)?
    var onIceCandidate: ((RTCIceCandidate) -> Void)?
    var onRemoteAudioTrack: ((RTCAudioTrack) -> Void)?
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("[PeerConnectionDelegate] Signaling state: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("[PeerConnectionDelegate] Added stream: \(stream.streamId)")
        // Capture remote audio track
        if let audioTrack = stream.audioTracks.first {
            print("[PeerConnectionDelegate] 🔊 Found remote audio track: \(audioTrack.trackId)")
            onRemoteAudioTrack?(audioTrack)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("[PeerConnectionDelegate] Removed stream: \(stream.streamId)")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("[PeerConnectionDelegate] Should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onIceConnectionStateChange?(newState)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("[PeerConnectionDelegate] ICE gathering state: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("[PeerConnectionDelegate] Generated ICE candidate")
        onIceCandidate?(candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("[PeerConnectionDelegate] Removed ICE candidates")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("[PeerConnectionDelegate] Opened data channel: \(dataChannel.label)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        onConnectionStateChange?(stateChanged)
    }
}

// MARK: - Data Channel Delegate

/// Delegate wrapper for RTCDataChannel callbacks
private final class DataChannelDelegate: NSObject, RTCDataChannelDelegate, @unchecked Sendable {
    var onMessage: ((String) -> Void)?
    var onStateChange: ((RTCDataChannelState) -> Void)?
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        onStateChange?(dataChannel.readyState)
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let message = String(data: buffer.data, encoding: .utf8) {
            onMessage?(message)
        }
    }
}
