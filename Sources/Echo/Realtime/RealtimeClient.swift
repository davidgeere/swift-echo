// RealtimeClient.swift
// Echo - Realtime API
// Main WebSocket client for the Realtime API with MANDATORY model validation

@preconcurrency import AVFoundation
import Foundation

/// Main client for interacting with the Realtime API via WebSocket
public actor RealtimeClient: TurnManagerDelegate {
    // MARK: - Properties

    private let apiKey: String
    private let configuration: RealtimeClientConfiguration
    private let eventEmitter: EventEmitter
    private let tools: [Tool]
    private let mcpServers: [MCPServer]

    // Delegate for internal coordination (direct calls instead of events)
    private weak var delegate: (any RealtimeClientDelegate)?

    // Tool executor for centralized tool execution
    private var toolExecutor: (any ToolExecuting)?

    // TurnManager for proper event routing
    private let turnManager: TurnManager?

    private var webSocket: WebSocketManager
    private var audioCapture: (any AudioCaptureProtocol)?
    private var audioPlayback: (any AudioPlaybackProtocol)?

    // Optional factory closures for creating audio components
    // Allows dependency injection while supporting both concrete and mock implementations
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
    ///   - toolExecutor: Optional ToolExecutor for executing tools
    ///   - delegate: Optional delegate for internal coordination
    ///   - audioCaptureFactory: Optional factory for creating audio capture (for testing)
    ///   - audioPlaybackFactory: Optional factory for creating audio playback (for testing)
    public init(
        apiKey: String,
        configuration: RealtimeClientConfiguration,
        eventEmitter: EventEmitter,
        tools: [Tool] = [],
        mcpServers: [MCPServer] = [],
        turnManager: TurnManager? = nil,
        toolExecutor: (any ToolExecuting)? = nil,
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

        // Wire up TurnManager delegate to self for interruption handling
        Task {
            await turnManager?.setDelegate(self)
        }
    }

    // MARK: - Delegate Management

    /// Sets the delegate for internal coordination
    /// - Parameter delegate: The delegate to set
    public func setDelegate(_ delegate: (any RealtimeClientDelegate)?) {
        self.delegate = delegate
    }

    /// Sets the tool executor for tool execution
    /// - Parameter executor: The tool executor to use
    public func setToolExecutor(_ executor: (any ToolExecuting)?) {
        self.toolExecutor = executor
    }

    // MARK: - TurnManagerDelegate

    /// Called by TurnManager when interruption is requested
    public func turnManagerDidRequestInterruption(_ manager: TurnManager) async {
        await stopAudioPlayback()
    }

    // MARK: - Audio Control

    /// Stops audio playback (for interruptions)
    private func stopAudioPlayback() async {
        await audioPlayback?.interrupt()
    }

    /// Submits a tool result back to OpenAI
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
        // This is MANDATORY. Only gpt-realtime and gpt-realtime-mini are supported.
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
            // to ensure we don't miss session.created
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

        // Remove notification observer
        #if os(iOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        #endif

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
        // Allow sending during .connecting (for session configuration)
        // but not when .disconnected or .failed
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
            // Create audio capture (use factory if provided, otherwise create concrete instance)
            let capture: any AudioCaptureProtocol
            if let factory = audioCaptureFactory {
                capture = await factory()
            } else {
                capture = AudioCapture(format: configuration.audioFormat)
            }
            
            try await capture.start { [weak self] base64Audio in
                guard let self = self else { return }

                // Send audio to server
                try? await self.send(.inputAudioBufferAppend(audio: base64Audio))
            }
            self.audioCapture = capture

            // Monitor input audio levels
            Task {
                let levelStream = await capture.audioLevelStream
                for await levels in levelStream {
                    await self.eventEmitter.emit(.inputLevelsChanged(levels: levels))
                }
            }

            // Create audio playback (use factory if provided, otherwise create concrete instance)
            let playback: any AudioPlaybackProtocol
            if let factory = audioPlaybackFactory {
                playback = await factory()
            } else {
                playback = AudioPlayback(format: configuration.audioFormat)
            }
            
            try await playback.start()
            self.audioPlayback = playback
            
            // Monitor output audio levels
            Task {
                let levelStream = await playback.audioLevelStream
                for await levels in levelStream {
                    await self.eventEmitter.emit(.outputLevelsChanged(levels: levels))
                }
            }

            // Set up route change observer for audio output changes
            #if os(iOS)
            await observeAudioRouteChanges()
            #endif

            // Emit audio started event after both capture and playback are ready
            await eventEmitter.emit(.audioStarted)
        } catch {
            // Emit audio stopped event if setup fails
            await eventEmitter.emit(.audioStopped)
            throw error
        }
    }

    /// Stops audio capture and playback
    public func stopAudio() async {
        // Only emit stopped event if audio was actually started
        let wasStarted = audioCapture != nil || audioPlayback != nil

        await audioCapture?.stop()
        await audioPlayback?.stop()
        audioCapture = nil
        audioPlayback = nil

        // Emit audio stopped event if audio was started
        if wasStarted {
            await eventEmitter.emit(.audioStopped)
        }
    }

    /// Mutes or unmutes audio input
    /// - Parameter muted: Whether to mute the microphone
    /// - Throws: RealtimeError if audio capture is not active
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
    /// - Parameter device: The audio output device to use
    /// - Throws: RealtimeError if audio playback is not active
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        guard let playback = audioPlayback else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "RealtimeClient", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Audio playback is not active"
                ])
            )
        }
        
        // CRITICAL FIX: Stop capture engine before route change (same as playback)
        // This prevents route caching issues
        let captureActiveBefore = await audioCapture?.isActive ?? false
        let needsCaptureRestart = captureActiveBefore
        
        if let capture = audioCapture, captureActiveBefore {
            // Stop the engine (keeps tap installed, ready for restart)
            await capture.pause()
            // Small delay to ensure capture fully stops
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        
        // Change playback route (this will stop/restart playback engine)
        try await playback.setAudioOutput(device: device)
        
        // CRITICAL FIX: Restart capture engine after route change
        // Both engines need to restart with the new route
        if let capture = audioCapture, needsCaptureRestart {
            do {
                try await capture.resume()
            } catch {
                // Don't throw - playback still works, just log the error
            }
        }
        
        // Emit event for output change
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
    
    /// Installs an audio tap on the playback engine's main mixer node for external monitoring
    /// - Parameters:
    ///   - bufferSize: The buffer size for the tap (default: 1024)
    ///   - format: The audio format for the tap (nil uses the output format)
    ///   - handler: The closure called with audio buffer data
    /// - Throws: RealtimeError if audio playback is not active
    public func installAudioTap(
        bufferSize: UInt32 = 1024,
        format: AVAudioFormat? = nil,
        handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) async throws {
        guard let playback = audioPlayback else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "RealtimeClient", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "Audio playback is not active"
                ])
            )
        }
        
        guard let engine = await playback.audioEngine else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "RealtimeClient", code: -4, userInfo: [
                    NSLocalizedDescriptionKey: "Audio engine is not available"
                ])
            )
        }
        
        let mixer = engine.mainMixerNode
        let tapFormat = format ?? mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat, block: handler)
    }
    
    /// Removes the audio tap from the playback engine's main mixer node
    public func removeAudioTap() async {
        guard let playback = audioPlayback,
              let engine = await playback.audioEngine else {
            return
        }
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    /// Send a text message to the Realtime API
    /// - Parameter text: The text message to send
    /// - Throws: RealtimeError if send fails
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
    /// - Parameter turnDetection: The turn detection mode to use
    /// - Throws: RealtimeError if send fails
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
        // Wait up to 10 seconds for session.created
        // NOTE: We don't consume messageStream here anymore because it would
        // race with startEventListener(). Instead, we rely on the fact that
        // startEventListener() will process the session.created event and set sessionId.
        // We just wait for sessionId to be set.

        let sessionId = try await withTimeout(seconds: 10) { @Sendable [weak self] () async throws -> String in
            guard let self = self else {
                throw RealtimeError.sessionInitializationFailed("Client deallocated")
            }

            // Poll for sessionId to be set by the event listener
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
        // Convert tools to SendableJSON format
        var allToolsJSON: [SendableJSON] = []

        // Add regular tools
        if !tools.isEmpty {
            allToolsJSON.append(contentsOf: tools.map { $0.toAPIFormat() })
        }

        // Add MCP servers as tools
        if !mcpServers.isEmpty {
            allToolsJSON.append(contentsOf: mcpServers.map { $0.toAPIFormat() })
        }

        let toolsJSON: [SendableJSON]? = allToolsJSON.isEmpty ? nil : allToolsJSON

        // Temperature rounding is handled in RealtimeSession.toRealtimeFormat()
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
                    // Unexpected disconnection
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
            // Notify delegate directly
            await delegate?.realtimeClient(self, didCommitAudioBuffer: itemId)
            // Also emit event for external observers
            await eventEmitter.emit(.userAudioBufferCommitted(itemId: itemId))

        // Speech detection
        // Route VAD events through TurnManager
        case .inputAudioBufferSpeechStarted:
            // Stop assistant playback when user starts speaking
            await audioPlayback?.interrupt()
            
            // Emit audio status change
            await eventEmitter.emit(.audioStatusChanged(status: .listening))

            // Route through TurnManager if available, otherwise emit directly
            if let turnManager = turnManager {
                await turnManager.handleUserStartedSpeaking()
            } else {
                // Notify delegate directly
                await delegate?.realtimeClientDidDetectUserSpeech(self)
                // Also emit event for external observers
                await eventEmitter.emit(.userStartedSpeaking)
            }

        case .inputAudioBufferSpeechStopped:
            // Emit processing status when speech stops
            await eventEmitter.emit(.audioStatusChanged(status: .processing))
            
            // Route through TurnManager if available, otherwise emit directly
            if let turnManager = turnManager {
                await turnManager.handleUserStoppedSpeaking()
            } else {
                // Notify delegate directly
                await delegate?.realtimeClientDidDetectUserSilence(self)
                // Also emit event for external observers
                await eventEmitter.emit(.userStoppedSpeaking)
            }

        // Transcription
        case .conversationItemInputAudioTranscriptionCompleted(let itemId, let transcript):
            currentTranscripts[itemId] = transcript
            // Notify delegate directly
            await delegate?.realtimeClient(self, didReceiveTranscript: transcript, itemId: itemId)
            // Also emit event for external observers
            await eventEmitter.emit(.userTranscriptionCompleted(transcript: transcript, itemId: itemId))

        // Audio response
        case .responseAudioDelta(_, _, _, _, let delta):
            // Emit speaking status when audio starts
            await eventEmitter.emit(.audioStatusChanged(status: .speaking))
            
            // Play audio chunk
            if let playback = audioPlayback {
                // Decode base64 to Data for the event
                if let audioData = Data(base64Encoded: delta) {
                    await eventEmitter.emit(.assistantAudioDelta(audioChunk: audioData))
                }

                try? await playback.enqueue(base64Audio: delta)
            }

        case .responseAudioTranscriptDelta(_, let itemId, _, _, let delta):
            // Track assistant item and accumulate text
            currentAssistantItemId = itemId
            currentAssistantText += delta
            await eventEmitter.emit(.assistantTextDelta(delta: delta))

        // Text response
        case .responseTextDelta(_, let itemId, _, _, let delta):
            // Track assistant item and accumulate text
            currentAssistantItemId = itemId
            currentAssistantText += delta
            await eventEmitter.emit(.assistantTextDelta(delta: delta))

        // Response lifecycle
        case .responseCreated:
            // Clear previous assistant text
            currentAssistantText = ""

            // Route through TurnManager if available
            if let turnManager = turnManager {
                await turnManager.handleAssistantStartedSpeaking()
            } else {
                await eventEmitter.emit(.assistantStartedSpeaking)
            }

        case .responseOutputItemAdded(_, _, let item):
            // Track the assistant's response item ID
            currentAssistantItemId = item.id
            // Notify delegate directly
            await delegate?.realtimeClient(self, didStartAssistantResponse: item.id)
            // Also emit event for external observers
            await eventEmitter.emit(.assistantResponseCreated(itemId: item.id))

        case .responseDone:
            // Emit idle status when response completes
            await eventEmitter.emit(.audioStatusChanged(status: .idle))
            
            // Route through TurnManager if available
            if let turnManager = turnManager {
                await turnManager.handleAssistantFinishedSpeaking()
            } else {
                await eventEmitter.emit(.assistantStoppedSpeaking)
            }

            // Emit response done with complete text
            if let itemId = currentAssistantItemId {
                // Notify delegate directly
                await delegate?.realtimeClient(self, didReceiveAssistantResponse: currentAssistantText, itemId: itemId)
                // Also emit event for external observers
                await eventEmitter.emit(.assistantResponseDone(itemId: itemId, text: currentAssistantText))
                // Clear for next response
                currentAssistantItemId = nil
                currentAssistantText = ""
            }

        // Function calls
        case .responseFunctionCallArgumentsDone(_, _, _, let callId, let name, let argumentsString):
            // Parse arguments string to SendableJSON
            let argumentsData = argumentsString.data(using: .utf8) ?? Data()
            let arguments = (try? SendableJSON.from(data: argumentsData)) ?? .null
            let toolCall = ToolCall(id: callId, name: name, arguments: arguments)
            
            // Emit event for external observers
            await eventEmitter.emit(.toolCallRequested(toolCall: toolCall))
            
            // Execute tool via executor if available, otherwise notify delegate
            if let executor = toolExecutor {
                let result = await executor.execute(toolCall: toolCall)
                // Submit the result back to OpenAI
                await submitToolResult(toolCallId: result.toolCallId, output: result.output)
            } else {
                // Notify delegate directly for custom handling
                await delegate?.realtimeClient(self, didReceiveToolCall: toolCall)
            }

        // Rate limits
        case .rateLimitsUpdated(_):
            // Could emit an event for rate limit tracking
            break

        // Other events
        default:
            // Log or handle other events as needed
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
    
    /// Observes audio route changes and emits events when output device changes
    #if os(iOS)
    private func observeAudioRouteChanges() async {
        let notificationCenter = NotificationCenter.default
        
        // Store observer for cleanup
        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task { [weak self] in
                guard let self = self,
                      let playback = await self.audioPlayback else { return }
                
                // Get current output device
                let currentDevice = await playback.currentAudioOutput
                
                // Emit event for output change
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
    /// - Parameters:
    ///   - model: Realtime model (MUST be .gptRealtime or .gptRealtimeMini)
    ///   - voice: Voice type
    ///   - audioFormat: Audio format
    ///   - turnDetection: Turn detection config
    ///   - instructions: System instructions
    ///   - enableTranscription: Enable transcription
    ///   - startAudioAutomatically: Auto-start audio
    ///   - temperature: Sampling temperature
    ///   - maxOutputTokens: Max output tokens
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
