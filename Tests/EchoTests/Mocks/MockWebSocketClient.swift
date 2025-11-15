// MockWebSocketClient.swift
// Echo Tests - Mock Infrastructure
// Mock WebSocket client for deterministic testing without real connections

import Foundation
@testable import Echo

/// Mock WebSocket client for testing
public actor MockWebSocketClient {
    private var isConnected = false
    private var messageQueue: [WebSocketMessage] = []
    private var receivedMessages: [WebSocketMessage] = []
    private var eventSequence: [ServerEvent] = []
    private var currentSequenceIndex = 0
    private var shouldFailConnection = false
    private var shouldDropMessages = false
    private var connectionDelay: TimeInterval = 0
    private var messageDelay: TimeInterval = 0
    private var disconnectAfterMessages: Int?
    private var errorToThrow: Error?
    
    /// WebSocket message types
    public enum WebSocketMessage: Sendable, Equatable {
        case text(String)
        case data(Data)
        case ping
        case pong
        case close(code: Int, reason: String?)
    }
    
    /// Recording of WebSocket interactions
    public struct Recording: Sendable {
        public let sentMessages: [WebSocketMessage]
        public let receivedMessages: [WebSocketMessage]
        public let events: [ServerEvent]
        public let duration: TimeInterval
        public let connectionEstablished: Bool
    }
    
    // MARK: - Configuration
    
    /// Set connection failure mode
    public func setConnectionFailure(_ shouldFail: Bool, delay: TimeInterval = 0) {
        self.shouldFailConnection = shouldFail
        self.connectionDelay = delay
    }
    
    /// Set message dropping mode
    public func setDropMessages(_ shouldDrop: Bool) {
        self.shouldDropMessages = shouldDrop
    }
    
    /// Set message delay
    public func setMessageDelay(_ delay: TimeInterval) {
        self.messageDelay = delay
    }
    
    /// Set automatic disconnect after N messages
    public func setDisconnectAfter(messages: Int) {
        self.disconnectAfterMessages = messages
    }
    
    /// Set error to throw on next operation
    public func setError(_ error: Error?) {
        self.errorToThrow = error
    }
    
    /// Load a pre-recorded event sequence
    public func loadEventSequence(_ events: [ServerEvent]) {
        self.eventSequence = events
        self.currentSequenceIndex = 0
    }
    
    // MARK: - Connection Management
    
    /// Connect to mock WebSocket
    public func connect() async throws {
        // Simulate connection delay
        if connectionDelay > 0 {
            try await Task.sleep(for: .seconds(connectionDelay))
        }
        
        // Check for connection failure
        if shouldFailConnection {
            throw WebSocketError.connectionFailed("Mock connection failure")
        }
        
        // Check for error injection
        if let error = errorToThrow {
            errorToThrow = nil
            throw error
        }
        
        isConnected = true
        
        // Send initial session.created event if sequence loaded
        if !eventSequence.isEmpty && currentSequenceIndex == 0 {
            await sendNextEventFromSequence()
        }
    }
    
    /// Disconnect from mock WebSocket
    public func disconnect(code: Int = 1000, reason: String? = nil) async {
        isConnected = false
        
        // Send close message
        let closeMessage = WebSocketMessage.close(code: code, reason: reason)
        receivedMessages.append(closeMessage)
        
        // Clear queues
        messageQueue.removeAll()
    }
    
    /// Check connection status
    public func getIsConnected() -> Bool {
        return isConnected
    }
    
    // MARK: - Message Handling
    
    /// Send a message through the mock WebSocket
    public func send(_ message: WebSocketMessage) async throws {
        guard isConnected else {
            throw WebSocketError.notConnected
        }
        
        // Check for error injection
        if let error = errorToThrow {
            errorToThrow = nil
            throw error
        }
        
        // Simulate message delay
        if messageDelay > 0 {
            try await Task.sleep(for: .seconds(messageDelay))
        }
        
        // Check if we should drop this message
        if shouldDropMessages {
            return // Silently drop
        }
        
        // Record the sent message
        receivedMessages.append(message)
        
        // Check for auto-disconnect
        if let disconnectAfter = disconnectAfterMessages {
            if receivedMessages.count >= disconnectAfter {
                await disconnect(code: 1001, reason: "Auto-disconnect after \(disconnectAfter) messages")
                return
            }
        }
        
        // Process the message and generate response
        await processMessage(message)
    }
    
    /// Send text message
    public func sendText(_ text: String) async throws {
        try await send(.text(text))
    }
    
    /// Send data message
    public func sendData(_ data: Data) async throws {
        try await send(.data(data))
    }
    
    /// Receive next message from queue
    public func receive() async throws -> WebSocketMessage? {
        guard isConnected else {
            throw WebSocketError.notConnected
        }
        
        if messageQueue.isEmpty {
            // If we have a sequence, send the next event
            if currentSequenceIndex < eventSequence.count {
                await sendNextEventFromSequence()
            }
        }
        
        return messageQueue.isEmpty ? nil : messageQueue.removeFirst()
    }
    
    /// Receive text message
    public func receiveText() async throws -> String? {
        guard let message = try await receive() else { return nil }
        
        if case .text(let text) = message {
            return text
        }
        return nil
    }
    
    // MARK: - Event Simulation
    
    /// Process incoming message and generate appropriate response
    private func processMessage(_ message: WebSocketMessage) async {
        guard case .text(let text) = message else { return }
        
        // Try to parse as JSON
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        // Generate response based on message type
        switch type {
        case "session.update":
            await simulateSessionUpdate()
            
        case "input_audio_buffer.append":
            // No immediate response for audio append
            break
            
        case "input_audio_buffer.commit":
            await simulateInputAudioCommit()
            
        case "conversation.item.create":
            await simulateConversationItemCreate(json)
            
        case "response.create":
            await simulateResponseCreate()
            
        case "response.cancel":
            await simulateResponseCancel()
            
        default:
            break
        }
    }
    
    /// Send next event from loaded sequence
    private func sendNextEventFromSequence() async {
        guard currentSequenceIndex < eventSequence.count else { return }
        
        let event = eventSequence[currentSequenceIndex]
        currentSequenceIndex += 1
        
        // Convert event to JSON and send
        if let jsonString = eventToJSON(event) {
            messageQueue.append(.text(jsonString))
        }
        
        // Schedule next event with small delay
        if currentSequenceIndex < eventSequence.count {
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await sendNextEventFromSequence()
            }
        }
    }
    
    /// Simulate session update response
    private func simulateSessionUpdate() async {
        let response = """
        {
            "type": "session.updated",
            "event_id": "mock_evt_\(UUID().uuidString)",
            "session": {
                "id": "mock_session",
                "object": "realtime.session",
                "model": "gpt-4o-realtime",
                "modalities": ["text", "audio"]
            }
        }
        """
        messageQueue.append(.text(response))
    }
    
    /// Simulate input audio commit response
    private func simulateInputAudioCommit() async {
        let response = """
        {
            "type": "input_audio_buffer.committed",
            "event_id": "mock_evt_\(UUID().uuidString)",
            "previous_item_id": null,
            "item_id": "item_\(UUID().uuidString)"
        }
        """
        messageQueue.append(.text(response))
    }
    
    /// Simulate conversation item creation
    private func simulateConversationItemCreate(_ json: [String: Any]) async {
        let itemId = "item_\(UUID().uuidString)"
        let response = """
        {
            "type": "conversation.item.created",
            "event_id": "mock_evt_\(UUID().uuidString)",
            "previous_item_id": null,
            "item": {
                "id": "\(itemId)",
                "object": "realtime.item",
                "type": "message",
                "status": "completed",
                "role": "user"
            }
        }
        """
        messageQueue.append(.text(response))
    }
    
    /// Simulate response creation
    private func simulateResponseCreate() async {
        let responseId = "resp_\(UUID().uuidString)"
        let itemId = "item_\(UUID().uuidString)"
        
        // 1. Response created
        let created = """
        {
            "type": "response.created",
            "event_id": "mock_evt_\(UUID().uuidString)",
            "response": {
                "id": "\(responseId)",
                "object": "realtime.response",
                "status": "in_progress"
            }
        }
        """
        messageQueue.append(.text(created))
        
        // 2. Response text delta
        let delta = """
        {
            "type": "response.text.delta",
            "event_id": "mock_evt_\(UUID().uuidString)",
            "response_id": "\(responseId)",
            "item_id": "\(itemId)",
            "output_index": 0,
            "content_index": 0,
            "delta": "Hello from mock WebSocket!"
        }
        """
        messageQueue.append(.text(delta))
        
        // 3. Response done
        let done = """
        {
            "type": "response.done",
            "event_id": "mock_evt_\(UUID().uuidString)",
            "response": {
                "id": "\(responseId)",
                "object": "realtime.response",
                "status": "completed",
                "output": [],
                "usage": {
                    "total_tokens": 50,
                    "input_tokens": 20,
                    "output_tokens": 30
                }
            }
        }
        """
        messageQueue.append(.text(done))
    }
    
    /// Simulate response cancellation
    private func simulateResponseCancel() async {
        let response = """
        {
            "type": "response.cancelled",
            "event_id": "mock_evt_\(UUID().uuidString)"
        }
        """
        messageQueue.append(.text(response))
    }
    
    // MARK: - Recording and Playback
    
    /// Get current recording
    public func getRecording(duration: TimeInterval) -> Recording {
        return Recording(
            sentMessages: receivedMessages,
            receivedMessages: messageQueue,
            events: eventSequence,
            duration: duration,
            connectionEstablished: isConnected
        )
    }
    
    /// Clear all messages and state
    public func reset() {
        isConnected = false
        messageQueue.removeAll()
        receivedMessages.removeAll()
        eventSequence.removeAll()
        currentSequenceIndex = 0
        shouldFailConnection = false
        shouldDropMessages = false
        connectionDelay = 0
        messageDelay = 0
        disconnectAfterMessages = nil
        errorToThrow = nil
    }
    
    // MARK: - Test Helpers
    
    /// Get all received messages
    public func getReceivedMessages() -> [WebSocketMessage] {
        return receivedMessages
    }
    
    /// Get pending message queue
    public func getPendingMessages() -> [WebSocketMessage] {
        return messageQueue
    }
    
    /// Inject a server event directly
    public func injectServerEvent(_ event: ServerEvent) async {
        if let jsonString = eventToJSON(event) {
            messageQueue.append(.text(jsonString))
        }
    }
    
    /// Inject an error event
    public func injectError(type: String, code: String, message: String) async {
        let errorEvent = """
        {
            "type": "error",
            "event_id": "mock_error_\(UUID().uuidString)",
            "error": {
                "type": "\(type)",
                "code": "\(code)",
                "message": "\(message)"
            }
        }
        """
        messageQueue.append(.text(errorEvent))
    }
    
    /// Convert ServerEvent to JSON string
    private func eventToJSON(_ event: ServerEvent) -> String? {
        // This is a simplified implementation
        // In practice, you'd need full serialization for all event types
        switch event {
        case .sessionCreated(let session):
            return """
            {
                "type": "session.created",
                "event_id": "mock_\(UUID().uuidString)",
                "session": {
                    "id": "\(session.id)",
                    "object": "realtime.session",
                    "model": "\(session.model ?? "gpt-4o-realtime")",
                    "voice": "\(session.voice ?? "alloy")"
                }
            }
            """
            
        case .error(let error):
            return """
            {
                "type": "error",
                "event_id": "mock_\(UUID().uuidString)",
                "error": {
                    "code": "\(error.code)",
                    "code": "\(error.code ?? "")",
                    "message": "\(error.message ?? "")"
                }
            }
            """
            
        case .inputAudioBufferSpeechStarted(let startMs, let itemId):
            return """
            {
                "type": "input_audio_buffer.speech_started",
                "event_id": "mock_\(UUID().uuidString)",
                "audio_start_ms": \(startMs),
                "item_id": "\(itemId)"
            }
            """
            
        case .inputAudioBufferSpeechStopped(let endMs, let itemId):
            return """
            {
                "type": "input_audio_buffer.speech_stopped",
                "event_id": "mock_\(UUID().uuidString)",
                "audio_end_ms": \(endMs),
                "item_id": "\(itemId)"
            }
            """
            
        default:
            // For other events, return a generic structure
            return nil
        }
    }
}

// MARK: - WebSocket Errors

public enum WebSocketError: Error, LocalizedError {
    case connectionFailed(String)
    case notConnected
    case messageSendFailed(String)
    case messageReceiveFailed(String)
    case invalidMessage(String)
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "WebSocket connection failed: \(reason)"
        case .notConnected:
            return "WebSocket is not connected"
        case .messageSendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .messageReceiveFailed(let reason):
            return "Failed to receive message: \(reason)"
        case .invalidMessage(let reason):
            return "Invalid message: \(reason)"
        case .timeout:
            return "WebSocket operation timed out"
        }
    }
}

// MARK: - Test Scenario Presets

extension MockWebSocketClient {
    /// Configure for successful conversation flow
    public func configureForSuccessfulConversation() async {
        let events: [ServerEvent] = [
            .sessionCreated(session: SessionInfo(
                id: "sess_test",
                model: "gpt-4o-realtime",
                voice: "alloy"
            ))
        ]
        
        await loadEventSequence(events)
    }
    
    /// Configure for error scenarios
    public func configureForErrors() async {
        await setConnectionFailure(false)
        
        // Inject various errors
        await injectError(
            type: "invalid_request_error",
            code: "invalid_model",
            message: "The model does not exist"
        )
    }
    
    /// Configure for audio streaming
    public func configureForAudioStreaming() async {
        // This would set up a sequence of audio-related events
        let events: [ServerEvent] = [
            .inputAudioBufferSpeechStarted(itemId: "item_audio_1", audioStartMs: 0),
            .inputAudioBufferSpeechStopped(itemId: "item_audio_1", audioEndMs: 2000),
            .inputAudioBufferCommitted(itemId: "item_audio_1", previousItemId: nil)
        ]
        
        await loadEventSequence(events)
    }
}
