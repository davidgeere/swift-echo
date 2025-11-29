// RealtimeClient.swift
// Echo - Realtime API
// Main WebSocket client for the Realtime API with MANDATORY model validation

import Foundation
#if os(iOS)
import AVFoundation
#endif

/// Main client for interacting with the Realtime API via WebSocket
public actor RealtimeClient {
    // MARK: - Properties

    private let apiKey: String
    private let configuration: RealtimeClientConfiguration
    private let eventEmitter: EventEmitter
    private let tools: [Tool]
    private let mcpServers: [MCPServer]

    // CRITICAL: Direct references instead of event listeners
    private weak var delegate: (any RealtimeClientDelegate)?
    private let toolExecutor: ToolExecutor?

    // Turn management - direct reference, not event-based
    private let turnManager: TurnManager?

    private var webSocket: WebSocketManager
    private var audioCapture: (any AudioCaptureProtocol)?
    private var audioPlayback: (any AudioPlaybackProtocol)?

    // Optional factory closures for creating audio components
    private let audioCaptureFactory: (@Sendable () async -> any AudioCaptureProtocol)?
    private let audioPlaybackFactory: (@Sendable () async -> any AudioPlaybackProtocol)?

    private var sessionId: String?
    private var sessionState: SessionState = .disconnected

    // Accumulated transcript for building messages
    private var currentTranscripts: [String: String] = [:]

    // Track current user message item ID for message queue
    private var currentUserItemId: String?

    // Track pending assistant response data
    private var currentAssistantItemId: String?
    private var currentAssistantText: String = ""
    
    // Stored for cleanup
    #if os(iOS)
    private var routeChangeObserver: NSObjectProtocol?
    #endif

    // MARK: - Initialization

    /// Creates a Realtime API client
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - configuration: Client configuration
    ///   - eventEmitter: Event emitter for sending events
    ///   - tools: Registered tools for function calling
    ///   - mcpServers: Registered MCP servers
    ///   - turnManager: Optional TurnManager for managing speaking turns
    ///   - toolExecutor: Optional tool executor for handling tool calls
    ///   - delegate: Optional delegate for internal event routing
    ///   - audioCaptureFactory: Optional factory for creating audio capture (for testing)
    ///   - audioPlaybackFactory: Optional factory for creating audio playback (for testing)
    public init(
        apiKey: String,
        configuration: RealtimeClientConfiguration,
        eventEmitter: EventEmitter,
        tools: [Tool] = [],
        mcpServers: [MCPServer] = [],
        turnManager: TurnManager? = nil,
        toolExecutor: ToolExecutor? = nil,
        delegate: (any RealtimeClientDelegate)? = nil,
        audioCaptureFactory: (@Sendable () async -> any AudioCaptureProtocol)? = nil,
        audioPlaybackFactory: (@Sendable () async -> any AudioPlaybackProtocol)? = nil
    ) {
        self.apiKey = apiKey
        self.configuration = configuration
        self.eventEmitter = eventEmitter
        self.tools = tools
        self.mcpServers = mcpServers
        self.turnManager = turnManager
        self.toolExecutor = toolExecutor
        self.delegate = delegate
        self.webSocket = WebSocketManager()
        self.audioCaptureFactory = audioCaptureFactory
        self.audioPlaybackFactory = audioPlaybackFactory
        
        // NO event listener Tasks here - all coordination is direct
    }
    
    deinit {
        // Clean up NotificationCenter observer
        #if os(iOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    /// Sets the delegate for internal event routing
    /// - Parameter delegate: The delegate to set
    public func setDelegate(_ delegate: any RealtimeClientDelegate) {
        self.delegate = delegate
    }

    /// Stops audio playback (called directly, not via events)
    public func interruptPlayback() async {
        await audioPlayback?.interrupt()
    }

    /// Submits a tool result back to OpenAI (called directly, not via events)
    /// - Parameters:
    ///   - toolCallId: The tool call ID
    ///   - output: The tool result output
    public func submitToolResult(toolCallId: String, output: String) async {
        do {
            // Create conversation item with function call output
            let outputItem: [String: Any] = [
                "type": "function_call_output",
                "call_id": toolCallId,
                "output": output
            ]

            let sendableItem = try SendableJSON.from(dictionary: outputItem)

            // Send the item and request a response
            try await send(.conversationItemCreate(item: sendableItem, previousItemId: nil))
            try await send(.responseCreate(response: nil))
            
            // Emit notification event (fire-and-forget)
            await eventEmitter.emit(.toolResultSubmitted(toolCallId: toolCallId, result: output))
        } catch {
            await eventEmitter.emit(.error(error: RealtimeError.eventEncodingFailed(error)))
        }
    }

    // MARK: - Connection Management

    /// Connects to the Realtime API
    /// - Throws: RealtimeError if connection fails or model is invalid
    public func connect() async throws {
        guard sessionState == .disconnected else {
            throw RealtimeError.alreadyConnected
        }

        sessionState = .connecting

        // CRITICAL: MODEL VALIDATION
        let modelString = configuration.model.rawValue

        guard ["gpt-realtime", "gpt-realtime-mini"].contains(modelString) else {
            sessionState = .failed
            throw RealtimeError.unsupportedModel(
                "Model '\(modelString)' is not supported. " +
                "Valid Realtime models: gpt-realtime, gpt-realtime-mini"
            )
        }

        // Build WebSocket URL with model parameter
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(modelString)") else {
            sessionState = .failed
            throw RealtimeError.connectionFailed(
                NSError(domain: "RealtimeClient", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid WebSocket URL"
                ])
            )
        }

        // Connect to WebSocket
        do {
            // CRITICAL: Start event listeners BEFORE connecting
            startEventListener()
            startConnectionStateMonitor()

            try await webSocket.connect(
                to: url,
                headers: [
                    "Authorization": "Bearer \(apiKey)",
                    "OpenAI-Beta": "realtime=v1"
                ]
            )

            // Wait for session.created event (up to 10 seconds)
            try await waitForSessionCreated()

            // Configure session
            try await configureSession()

            // Start audio if configured
            if configuration.startAudioAutomatically {
                try await startAudio()
            }

            sessionState = .connected

            // Emit connection event
            await eventEmitter.emit(.connectionStatusChanged(isConnected: true))

        } catch {
            sessionState = .failed
            // Clean up WebSocket on failure
            await webSocket.disconnect()
            throw RealtimeError.connectionFailed(error)
        }
    }

    /// Disconnects from the Realtime API
    public func disconnect() async {
        guard sessionState != .disconnected else { return }

        // Stop audio
        await stopAudio()

        // Close WebSocket
        await webSocket.disconnect()

        sessionState = .disconnected
        sessionId = nil

        // Emit disconnection event
        await eventEmitter.emit(.connectionStatusChanged(isConnected: false))
    }

    // MARK: - Event Sending

    /// Sends a client event to the server
    /// - Parameter event: The client event to send
    /// - Throws: RealtimeError if not connected or sending fails
    public func send(_ event: ClientEvent) async throws {
        guard sessionState != .disconnected && sessionState != .failed else {
            throw RealtimeError.notConnected
        }

        do {
            let json = try event.toJSON()
            try await webSocket.send(json)
        } catch {
            throw RealtimeError.eventEncodingFailed(error)
        }
    }

    // MARK: - Audio Management

    /// Starts audio capture and playback
    public func startAudio() async throws {
        // Emit audio starting event
        await eventEmitter.emit(.audioStarting)

        do {
            // Create audio capture
            let capture: any AudioCaptureProtocol
            if let factory = audioCaptureFactory {
                capture = await factory()
            } else {
                capture = AudioCapture(format: configuration.audioFormat)
            }
            
            try await capture.start { [weak self] base64Audio in
                guard let self = self else { return }
                try? await self.send(.inputAudioBufferAppend(audio: base64Audio))
            }
            self.audioCapture = capture

            // Monitor audio levels with direct callback pattern
            Task {
                let levelStream = await capture.audioLevelStream
                for await level in levelStream {
                    await self.eventEmitter.emit(.audioLevelChanged(level: level))
                }
            }

            // Create audio playback
            let playback: any AudioPlaybackProtocol
            if let factory = audioPlaybackFactory {
                playback = await factory()
            } else {
                playback = AudioPlayback(format: configuration.audioFormat)
            }
            
            try await playback.start()
            self.audioPlayback = playback

            // Set up route change observer for audio output changes
            #if os(iOS)
            setupAudioRouteChangeObserver()
            #endif

            // Emit audio started event after both capture and playback are ready
            await eventEmitter.emit(.audioStarted)
        } catch {
            await eventEmitter.emit(.audioStopped)
            throw error
        }
    }

    /// Stops audio capture and playback
    public func stopAudio() async {
        let wasStarted = audioCapture != nil || audioPlayback != nil

        await audioCapture?.stop()
        await audioPlayback?.stop()
        audioCapture = nil
        audioPlayback = nil

        if wasStarted {
            await eventEmitter.emit(.audioStopped)
        }
    }

    /// Mutes or unmutes audio input
    public func setMuted(_ muted: Bool) async throws {
        guard let capture = audioCapture else {
            throw RealtimeError.audioCaptureFailed(
                NSError(domain: "RealtimeClient", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Audio capture is not active"
                ])
            )
        }

        if muted {
            await capture.pause()
        } else {
            try await capture.resume()
        }
    }

    /// Sets the audio output device
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        guard let playback = audioPlayback else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "RealtimeClient", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Audio playback is not active"
                ])
            )
        }
        
        let captureActiveBefore = await audioCapture?.isActive ?? false
        let needsCaptureRestart = captureActiveBefore
        
        if let capture = audioCapture, captureActiveBefore {
            await capture.pause()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        
        try await playback.setAudioOutput(device: device)
        
        if let capture = audioCapture, needsCaptureRestart {
            do {
                try await capture.resume()
            } catch {
                // Don't throw - playback still works
            }
        }
        
        let currentDevice = await playback.currentAudioOutput
        await eventEmitter.emit(.audioOutputChanged(device: currentDevice))
    }
    
    /// List of available audio output devices
    public var availableAudioOutputDevices: [AudioOutputDeviceType] {
        get async {
            return await audioPlayback?.availableAudioOutputDevices ?? []
        }
    }
    
    /// Current active audio output device
    public var currentAudioOutput: AudioOutputDeviceType {
        get async {
            return await audioPlayback?.currentAudioOutput ?? .systemDefault
        }
    }

    /// Send a text message to the Realtime API
    public func sendUserMessage(_ text: String) async throws {
        let item: SendableJSON = .object([
            "type": .string("message"),
            "role": .string("user"),
            "content": .array([
                .object([
                    "type": .string("input_text"),
                    "text": .string(text)
                ])
            ])
        ])

        try await send(.conversationItemCreate(item: item, previousItemId: nil))
        try await send(.responseCreate(response: nil))
    }

    /// Update the session configuration
    public func updateSessionConfig(turnDetection: TurnDetection) async throws {
        var sessionConfig: [String: SendableJSON] = [:]

        switch turnDetection {
        case .automatic(let config):
            sessionConfig["turn_detection"] = .object([
                "type": .string(config.type.rawValue),
                "threshold": .number(config.threshold),
                "prefix_padding_ms": .number(Double(config.prefixPaddingMs)),
                "silence_duration_ms": .number(Double(config.silenceDurationMs))
            ])
        case .manual:
            sessionConfig["turn_detection"] = .object([
                "type": .string("server_vad"),
                "threshold": .number(0.5),
                "silence_duration_ms": .number(Double(Int.max)),
                "prefix_padding_ms": .number(300.0)
            ])
        case .disabled:
            sessionConfig["turn_detection"] = SendableJSON.null
        }

        try await send(.sessionUpdate(session: .object(sessionConfig)))
    }

    // MARK: - Private Helpers

    private func waitForSessionCreated() async throws {
        let sessionId = try await withTimeout(seconds: 10) { @Sendable [weak self] () async throws -> String in
            guard let self = self else {
                throw RealtimeError.sessionInitializationFailed("Client deallocated")
            }

            while await self.sessionId == nil {
                try await Task.sleep(for: .milliseconds(100))
            }

            guard let id = await self.sessionId else {
                throw RealtimeError.sessionInitializationFailed("Session ID not set")
            }

            return id
        }

        self.sessionId = sessionId
    }

    private func configureSession() async throws {
        var allToolsJSON: [SendableJSON] = []

        if !tools.isEmpty {
            allToolsJSON.append(contentsOf: tools.map { $0.toAPIFormat() })
        }

        if !mcpServers.isEmpty {
            allToolsJSON.append(contentsOf: mcpServers.map { $0.toAPIFormat() })
        }

        let toolsJSON: [SendableJSON]? = allToolsJSON.isEmpty ? nil : allToolsJSON

        let session = RealtimeSession(
            model: configuration.model,
            voice: configuration.voice,
            inputAudioFormat: configuration.audioFormat,
            outputAudioFormat: configuration.audioFormat,
            inputAudioTranscription: configuration.enableTranscription ? InputAudioTranscription() : nil,
            turnDetection: configuration.turnDetection,
            instructions: configuration.instructions,
            tools: toolsJSON,
            temperature: configuration.temperature,
            maxResponseOutputTokens: configuration.maxOutputTokens
        )

        let sessionDict = session.toRealtimeFormat()
        let sessionJSON = try SendableJSON.from(dictionary: sessionDict)
        try await send(.sessionUpdate(session: sessionJSON))
    }

    private func startEventListener() {
        Task {
            for await message in webSocket.messageStream {
                await handleServerMessage(message)
            }
        }
    }

    private func startConnectionStateMonitor() {
        Task {
            for await isConnected in webSocket.connectionStateStream {
                if !isConnected && sessionState == .connected {
                    sessionState = .disconnected
                    await eventEmitter.emit(.connectionStatusChanged(isConnected: false))
                }
            }
        }
    }

    private func handleServerMessage(_ message: String) async {
        do {
            let event = try ServerEvent.parse(from: message)
            await handleServerEvent(event)
        } catch {
            await eventEmitter.emit(.error(error: RealtimeError.eventDecodingFailed(error)))
        }
    }

    private func handleServerEvent(_ event: ServerEvent) async {
        switch event {
        // Session events
        case .sessionCreated(let session):
            self.sessionId = session.id

        // Error events
        case .error(let code, let message, _):
            await eventEmitter.emit(.error(error: RealtimeError.serverError(code: code, message: message)))

        // Audio buffer committed - creates message slot
        case .inputAudioBufferCommitted(let itemId, _):
            currentUserItemId = itemId
            
            // Notify delegate directly (no event-based coordination)
            await delegate?.realtimeClient(self, didCommitAudioBuffer: itemId)
            
            // Emit notification event (fire-and-forget for SDK users)
            await eventEmitter.emit(.userAudioBufferCommitted(itemId: itemId))

        // Speech detection - route through TurnManager directly
        case .inputAudioBufferSpeechStarted:
            // Stop assistant playback when user starts speaking (direct call)
            await audioPlayback?.interrupt()
            
            await eventEmitter.emit(.audioStatusChanged(status: .listening))

            // Route through TurnManager if available
            if let turnManager = turnManager {
                await turnManager.handleUserStartedSpeaking()
            } else {
                await delegate?.realtimeClientDidDetectUserSpeech(self)
                await eventEmitter.emit(.userStartedSpeaking)
            }

        case .inputAudioBufferSpeechStopped:
            await eventEmitter.emit(.audioStatusChanged(status: .processing))
            
            if let turnManager = turnManager {
                await turnManager.handleUserStoppedSpeaking()
            } else {
                await delegate?.realtimeClientDidDetectUserSilence(self)
                await eventEmitter.emit(.userStoppedSpeaking)
            }

        // Transcription
        case .conversationItemInputAudioTranscriptionCompleted(let itemId, let transcript):
            currentTranscripts[itemId] = transcript
            
            // Notify delegate directly
            await delegate?.realtimeClient(self, didReceiveTranscript: transcript, itemId: itemId)
            
            await eventEmitter.emit(.userTranscriptionCompleted(transcript: transcript, itemId: itemId))

        // Audio response
        case .responseAudioDelta(_, _, _, _, let delta):
            await eventEmitter.emit(.audioStatusChanged(status: .speaking))
            
            if let playback = audioPlayback {
                if let audioData = Data(base64Encoded: delta) {
                    await eventEmitter.emit(.assistantAudioDelta(audioChunk: audioData))
                }
                try? await playback.enqueue(base64Audio: delta)
            }

        case .responseAudioTranscriptDelta(_, let itemId, _, _, let delta):
            currentAssistantItemId = itemId
            currentAssistantText += delta
            await eventEmitter.emit(.assistantTextDelta(delta: delta))

        // Text response
        case .responseTextDelta(_, let itemId, _, _, let delta):
            currentAssistantItemId = itemId
            currentAssistantText += delta
            await eventEmitter.emit(.assistantTextDelta(delta: delta))

        // Response lifecycle
        case .responseCreated:
            currentAssistantText = ""

            if let turnManager = turnManager {
                await turnManager.handleAssistantStartedSpeaking()
            } else {
                await eventEmitter.emit(.assistantStartedSpeaking)
            }

        case .responseOutputItemAdded(_, _, let item):
            currentAssistantItemId = item.id
            
            // Notify delegate directly
            await delegate?.realtimeClient(self, didStartAssistantResponse: item.id)
            
            await eventEmitter.emit(.assistantResponseCreated(itemId: item.id))

        case .responseDone:
            await eventEmitter.emit(.audioStatusChanged(status: .idle))
            
            if let turnManager = turnManager {
                await turnManager.handleAssistantFinishedSpeaking()
            } else {
                await delegate?.realtimeClientDidFinishAssistantResponse(self)
                await eventEmitter.emit(.assistantStoppedSpeaking)
            }

            if let itemId = currentAssistantItemId {
                // Notify delegate directly
                await delegate?.realtimeClient(self, didReceiveAssistantResponse: currentAssistantText, itemId: itemId)
                
                await eventEmitter.emit(.assistantResponseDone(itemId: itemId, text: currentAssistantText))
                currentAssistantItemId = nil
                currentAssistantText = ""
            }

        // Function calls - execute directly via ToolExecutor
        case .responseFunctionCallArgumentsDone(_, _, _, let callId, let name, let argumentsString):
            let argumentsData = argumentsString.data(using: .utf8) ?? Data()
            let arguments = (try? SendableJSON.from(data: argumentsData)) ?? .null
            let toolCall = ToolCall(id: callId, name: name, arguments: arguments)
            
            // Emit event for SDK users first
            await eventEmitter.emit(.toolCallRequested(toolCall: toolCall))
            
            // Execute tool directly (not via event listener)
            if let executor = toolExecutor {
                let result = await executor.execute(toolCall: toolCall)
                await submitToolResult(toolCallId: callId, output: result.output)
            } else {
                // Notify delegate if no executor
                await delegate?.realtimeClient(self, didReceiveToolCall: toolCall)
            }

        // Rate limits
        case .rateLimitsUpdated(_):
            break

        // Other events
        default:
            break
        }
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw RealtimeError.timeout
            }

            guard let result = try await group.next() else {
                throw RealtimeError.timeout
            }

            group.cancelAll()
            return result
        }
    }
    
    /// Sets up audio route change observer
    #if os(iOS)
    private func setupAudioRouteChangeObserver() {
        // Remove any existing observer first
        if let existing = routeChangeObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task { [weak self] in
                guard let self = self,
                      let playback = await self.audioPlayback else { return }
                
                let currentDevice = await playback.currentAudioOutput
                await self.eventEmitter.emit(.audioOutputChanged(device: currentDevice))
            }
        }
    }
    #endif
}

// MARK: - Configuration

/// Configuration for the Realtime API client
public struct RealtimeClientConfiguration: Sendable {
    /// The Realtime model to use (MUST be gpt-realtime or gpt-realtime-mini)
    public let model: RealtimeModel

    /// Voice for text-to-speech
    public let voice: VoiceType

    /// Audio format for input and output
    public let audioFormat: AudioFormat

    /// Turn detection configuration
    public let turnDetection: TurnDetection?

    /// System instructions for the model
    public let instructions: String?

    /// Whether to enable audio transcription
    public let enableTranscription: Bool

    /// Whether to start audio automatically on connection
    public let startAudioAutomatically: Bool

    /// Sampling temperature
    public let temperature: Double?

    /// Maximum output tokens
    public let maxOutputTokens: Int?

    /// Creates a configuration
    public init(
        model: RealtimeModel,
        voice: VoiceType = .alloy,
        audioFormat: AudioFormat = .pcm16,
        turnDetection: TurnDetection? = .default,
        instructions: String? = nil,
        enableTranscription: Bool = true,
        startAudioAutomatically: Bool = true,
        temperature: Double? = 0.8,
        maxOutputTokens: Int? = nil
    ) {
        self.model = model
        self.voice = voice
        self.audioFormat = audioFormat
        self.turnDetection = turnDetection
        self.instructions = instructions
        self.enableTranscription = enableTranscription
        self.startAudioAutomatically = startAudioAutomatically
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
    }

    /// Default configuration using gpt-realtime model
    public static let `default` = RealtimeClientConfiguration(
        model: .gptRealtime,
        voice: .alloy,
        audioFormat: .pcm16,
        turnDetection: .default,
        enableTranscription: true,
        startAudioAutomatically: true
    )

    /// Low-latency configuration using gpt-realtime-mini
    public static let lowLatency = RealtimeClientConfiguration(
        model: .gptRealtimeMini,
        voice: .alloy,
        audioFormat: .pcm16,
        turnDetection: .responsive,
        enableTranscription: true,
        startAudioAutomatically: true
    )
}
