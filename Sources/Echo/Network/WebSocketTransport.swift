// WebSocketTransport.swift
// Echo - Network Layer
// WebSocket implementation of RealtimeTransportProtocol

import Foundation

/// WebSocket-based transport for the Realtime API
///
/// This transport sends audio as base64-encoded chunks via `input_audio_buffer.append`
/// events and receives audio via `response.output_audio.delta` events. It uses
/// URLSession's WebSocket implementation for the underlying connection.
public actor WebSocketTransport: RealtimeTransportProtocol {
    // MARK: - Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var _isConnected: Bool = false
    private var isIntentionalDisconnect: Bool = false
    
    /// Stream of received text messages from the WebSocket
    public let eventStream: AsyncStream<String>
    private let eventContinuation: AsyncStream<String>.Continuation
    
    /// Stream of connection state changes
    public let connectionStateStream: AsyncStream<Bool>
    private let connectionStateContinuation: AsyncStream<Bool>.Continuation
    
    // MARK: - RealtimeTransportProtocol Properties
    
    /// WebSocket transport does not handle audio natively
    public var handlesAudioNatively: Bool { false }
    
    /// Whether the transport is currently connected
    public var isConnected: Bool { _isConnected }
    
    // MARK: - Initialization
    
    public init() {
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
    
    /// Connects to the Realtime API via WebSocket
    ///
    /// - Parameters:
    ///   - apiKey: The OpenAI API key (used directly for authentication)
    ///   - model: The model identifier (e.g., "gpt-realtime")
    ///   - sessionConfigJSON: Optional session configuration as JSON (not used during connect for WebSocket)
    /// - Throws: RealtimeTransportError if connection fails
    public func connect(apiKey: String, model: String, sessionConfigJSON: String?) async throws {
        print("[WebSocketTransport] 🔌 Connecting to Realtime API with model: \(model)")
        
        guard !_isConnected else {
            throw RealtimeTransportError.alreadyConnected
        }
        
        // Build WebSocket URL with model parameter
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else {
            throw RealtimeTransportError.connectionFailed(
                NSError(domain: "WebSocketTransport", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid WebSocket URL"
                ])
            )
        }
        
        // Create URLRequest with headers
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        // Create URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        
        let session = URLSession(configuration: configuration)
        self.urlSession = session
        
        // Create WebSocket task
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        
        print("[WebSocketTransport] 🚀 Resuming WebSocket task...")
        task.resume()
        
        // Mark as connected
        _isConnected = true
        
        // Start receiving messages
        receiveMessage()
        
        // Yield connection state
        connectionStateContinuation.yield(true)
        print("[WebSocketTransport] ✅ WebSocket connection successful")
    }
    
    /// Disconnects from the WebSocket gracefully
    public func disconnect() async {
        guard _isConnected else { return }
        
        print("[WebSocketTransport] 🔌 Disconnecting gracefully...")
        
        isIntentionalDisconnect = true
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        cleanupResources()
        connectionStateContinuation.yield(false)
        
        print("[WebSocketTransport] ✅ Disconnected cleanly")
    }
    
    /// Sends a client event as JSON to the server
    ///
    /// - Parameter eventJSON: The JSON string representation of the client event
    /// - Throws: RealtimeTransportError if sending fails
    public func send(eventJSON: String) async throws {
        guard _isConnected, let task = webSocketTask else {
            throw RealtimeTransportError.notConnected
        }
        
        let message = URLSessionWebSocketTask.Message.string(eventJSON)
        do {
            try await task.send(message)
        } catch {
            throw RealtimeTransportError.sendFailed(error)
        }
    }
    
    /// Sends base64-encoded audio to the server via input_audio_buffer.append
    ///
    /// - Parameter base64Audio: Base64-encoded PCM16 audio data
    /// - Throws: RealtimeTransportError if sending fails
    public func sendAudio(_ base64Audio: String) async throws {
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: event),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw RealtimeTransportError.sendFailed(
                NSError(domain: "WebSocketTransport", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to serialize audio event"
                ])
            )
        }
        
        try await send(eventJSON: jsonString)
    }
    
    /// No-op for WebSocket transport (audio handled by AudioCapture)
    public func setupLocalAudio() async throws {
        // WebSocket transport uses AudioCapture for local audio
    }
    
    /// No-op for WebSocket transport (audio handled by AudioCapture)
    public func setLocalAudioMuted(_ muted: Bool) async {
        // WebSocket transport uses AudioCapture for muting
    }
    
    // MARK: - Private Helpers
    
    private nonisolated func receiveMessage() {
        Task {
            await _receiveMessage()
        }
    }
    
    private func _receiveMessage() async {
        guard let task = webSocketTask, _isConnected else { return }
        
        do {
            let message = try await task.receive()
            
            switch message {
            case .string(let text):
                eventContinuation.yield(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    eventContinuation.yield(text)
                }
            @unknown default:
                break
            }
            
            if _isConnected {
                receiveMessage()
            }
        } catch {
            if !isIntentionalDisconnect {
                print("[WebSocketTransport] ❌ Receive error: \(error)")
            }
            handleDisconnection()
        }
    }
    
    private func handleDisconnection() {
        let wasIntentional = isIntentionalDisconnect
        cleanupResources()
        
        if !wasIntentional {
            connectionStateContinuation.yield(false)
        }
    }
    
    private func cleanupResources() {
        _isConnected = false
        isIntentionalDisconnect = false
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }
    
    deinit {
        eventContinuation.finish()
        connectionStateContinuation.finish()
    }
}

