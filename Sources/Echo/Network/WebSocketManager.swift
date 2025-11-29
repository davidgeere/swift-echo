// WebSocketManager.swift
// Echo - Network Layer
// URLSession-based WebSocket client for Realtime API

import Foundation

/// Manages WebSocket connections using URLSession for the Realtime API.
/// Handles connection lifecycle and message sending/receiving.
public actor WebSocketManager {
    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected: Bool = false
    private var isIntentionalDisconnect: Bool = false

    /// Stream of received text messages from the WebSocket
    public let messageStream: AsyncStream<String>
    private let messageContinuation: AsyncStream<String>.Continuation

    /// Stream of connection state changes
    public let connectionStateStream: AsyncStream<Bool>
    private let connectionStateContinuation: AsyncStream<Bool>.Continuation

    // MARK: - Initialization

    public init() {
        var messageCont: AsyncStream<String>.Continuation?
        self.messageStream = AsyncStream { continuation in
            messageCont = continuation
        }
        self.messageContinuation = messageCont!

        var connectionCont: AsyncStream<Bool>.Continuation?
        self.connectionStateStream = AsyncStream { continuation in
            connectionCont = continuation
        }
        self.connectionStateContinuation = connectionCont!
    }

    // MARK: - Connection Management

    /// Connects to a WebSocket URL with optional headers
    /// - Parameters:
    ///   - url: The WebSocket URL (wss:// or ws://)
    ///   - headers: Additional HTTP headers to send during the upgrade
    /// - Throws: WebSocketError if connection fails
    public func connect(to url: URL, headers: [String: String] = [:]) async throws {
        print("[WebSocketManager] 🔌 Attempting to connect to: \(url.absoluteString)")

        guard !isConnected else {
            print("[WebSocketManager] ❌ Already connected")
            throw WebSocketError.alreadyConnected
        }

        // Create URLRequest with headers
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Create URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300

        let session = URLSession(configuration: configuration)
        self.urlSession = session

        // Create WebSocket task
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task

        print("[WebSocketManager] 🚀 Resuming WebSocket task...")
        task.resume()

        // Mark as connected immediately - URLSession manages the actual connection state
        isConnected = true

        // Start receiving messages AFTER marking as connected
        receiveMessage()

        // Yield connection state
        connectionStateContinuation.yield(true)
        print("[WebSocketManager] ✅ WebSocket connection successful")
    }

    /// Disconnects from the WebSocket gracefully
    public func disconnect() async {
        guard isConnected else { return }

        print("[WebSocketManager] 🔌 Disconnecting gracefully...")
        
        // Mark this as an intentional disconnect to suppress error logging
        isIntentionalDisconnect = true
        
        // Stop the receive loop first by setting isConnected to false
        // This prevents new receive calls from being scheduled
        // Note: isConnected will be set to false in cleanupResources()
        
        // Close the WebSocket connection gracefully with normalClosure (1000)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        
        // Clean up resources (this will set isConnected = false)
        cleanupResources()
        
        // Notify connection state change
        connectionStateContinuation.yield(false)
        
        print("[WebSocketManager] ✅ Disconnected cleanly")
    }

    // MARK: - Message Sending

    /// Sends a text message over the WebSocket
    /// - Parameter text: The text to send
    /// - Throws: WebSocketError if not connected or send fails
    public func send(_ text: String) async throws {
        guard isConnected, let task = webSocketTask else {
            throw WebSocketError.notConnected
        }

        let message = URLSessionWebSocketTask.Message.string(text)
        try await task.send(message)
    }

    /// Sends binary data over the WebSocket
    /// - Parameter data: The binary data to send
    /// - Throws: WebSocketError if not connected or send fails
    public func send(_ data: Data) async throws {
        guard isConnected, let task = webSocketTask else {
            throw WebSocketError.notConnected
        }

        let message = URLSessionWebSocketTask.Message.data(data)
        try await task.send(message)
    }

    // MARK: - Callback-Based Receiving (New Pattern)
    
    /// Message callback type for callback-based receiving
    public typealias MessageCallback = @Sendable (String) async -> Void
    
    /// Disconnect callback type for callback-based receiving
    public typealias DisconnectCallback = @Sendable () async -> Void
    
    /// Stored callbacks for callback-based pattern
    private var onMessageCallback: MessageCallback?
    private var onDisconnectCallback: DisconnectCallback?
    
    /// Starts receiving messages with direct callbacks instead of streams.
    /// This eliminates the need for external Tasks iterating streams.
    /// - Parameters:
    ///   - onMessage: Called when a message is received
    ///   - onDisconnect: Called when disconnected
    public func startReceiving(
        onMessage: @escaping MessageCallback,
        onDisconnect: @escaping DisconnectCallback
    ) {
        self.onMessageCallback = onMessage
        self.onDisconnectCallback = onDisconnect
        
        // Start the receive loop
        receiveMessageWithCallback()
    }
    
    /// Receives messages and calls the callback directly
    private nonisolated func receiveMessageWithCallback() {
        Task {
            await _receiveMessageWithCallback()
        }
    }
    
    private func _receiveMessageWithCallback() async {
        guard let task = webSocketTask, isConnected else {
            return
        }
        
        do {
            let message = try await task.receive()
            
            switch message {
            case .string(let text):
                // Call the callback directly instead of yielding to stream
                if let callback = onMessageCallback {
                    await callback(text)
                }
                // Also yield to stream for backwards compatibility
                messageContinuation.yield(text)
                
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    if let callback = onMessageCallback {
                        await callback(text)
                    }
                    messageContinuation.yield(text)
                }
                
            @unknown default:
                break
            }
            
            // Continue receiving if still connected
            if isConnected {
                receiveMessageWithCallback()
            }
        } catch {
            if !isIntentionalDisconnect {
                print("[WebSocketManager] ❌ Receive error: \(error)")
            }
            handleDisconnectionWithCallback()
        }
    }
    
    private func handleDisconnectionWithCallback() {
        let wasIntentional = isIntentionalDisconnect
        let callback = onDisconnectCallback
        
        cleanupResourcesWithCallbacks()
        
        if !wasIntentional {
            connectionStateContinuation.yield(false)
            
            // Call disconnect callback
            if let callback = callback {
                Task {
                    await callback()
                }
            }
        }
    }
    
    private func cleanupResourcesWithCallbacks() {
        isConnected = false
        isIntentionalDisconnect = false
        onMessageCallback = nil
        onDisconnectCallback = nil
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }
    
    // MARK: - Private Helpers (Legacy Stream Pattern)

    private nonisolated func receiveMessage() {
        Task {
            await _receiveMessage()
        }
    }

    private func _receiveMessage() async {
        guard let task = webSocketTask, isConnected else {
            print("[WebSocketManager] ⚠️ Cannot receive: task=\(webSocketTask != nil), connected=\(isConnected)")
            return
        }

        do {
            print("[WebSocketManager] 📥 Waiting for message...")
            let message = try await task.receive()

            // Process the message
            switch message {
            case .string(let text):
                print("[WebSocketManager] 📨 Received text message: \(text.prefix(100))...")
                messageContinuation.yield(text)
            case .data(let data):
                print("[WebSocketManager] 📨 Received binary message: \(data.count) bytes")
                if let text = String(data: data, encoding: .utf8) {
                    messageContinuation.yield(text)
                }
            @unknown default:
                print("[WebSocketManager] ⚠️ Unknown message type received")
            }

            // Continue receiving if still connected
            if isConnected {
                receiveMessage()
            }
        } catch {
            // Only log errors if this wasn't an intentional disconnect
            if !isIntentionalDisconnect {
                print("[WebSocketManager] ❌ Receive error: \(error)")
                print("[WebSocketManager] ❌ Error type: \(type(of: error))")
            }
            handleDisconnection()
        }
    }

    private func handleDisconnection() {
        // Check if this was an intentional disconnect before cleanup
        let wasIntentional = isIntentionalDisconnect
        
        // Clean up resources first (this will reset flags)
        cleanupResources()
        
        // Only yield connection state change if not already handled by disconnect()
        if !wasIntentional {
            connectionStateContinuation.yield(false)
        }
    }

    private func cleanupResources() {
        // Set connection state
        isConnected = false
        
        // Reset the intentional disconnect flag early to avoid race conditions
        isIntentionalDisconnect = false
        
        // Clean up network resources
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    deinit {
        messageContinuation.finish()
        connectionStateContinuation.finish()
    }
}

// MARK: - WebSocket Errors

public enum WebSocketError: Error, LocalizedError {
    case invalidURL
    case alreadyConnected
    case notConnected
    case connectionFailed(Error)
    case sslConfigurationFailed(Error)
    case sendFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .alreadyConnected:
            return "WebSocket is already connected"
        case .notConnected:
            return "WebSocket is not connected"
        case .connectionFailed(let error):
            return "WebSocket connection failed: \(error.localizedDescription)"
        case .sslConfigurationFailed(let error):
            return "SSL configuration failed: \(error.localizedDescription)"
        case .sendFailed(let error):
            return "Failed to send WebSocket message: \(error.localizedDescription)"
        }
    }
}
