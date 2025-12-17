// Conversation.swift
// Echo - Core  
// Manages a single conversation with mode switching support

@preconcurrency import AVFoundation
@preconcurrency import Foundation
import Observation

/// Manages a single conversation with seamless mode switching between audio and text
@MainActor
@Observable
public class Conversation: RealtimeClientDelegate {
    // MARK: - Properties

    /// Unique conversation ID
    public let id: String

    /// Current conversation mode
    public private(set) var mode: EchoMode
    
    /// Current input audio levels (microphone) with frequency bands
    public private(set) var inputLevels: AudioLevels = .zero
    
    /// Current output audio levels (speaker) with frequency bands
    public private(set) var outputLevels: AudioLevels = .zero

    /// Message queue for proper sequencing
    private let messageQueue: MessageQueue

    /// Realtime API client (used for both audio and text modes)
    private var realtimeClient: RealtimeClient?

    /// Event emitter for publishing events
    private let eventEmitter: EventEmitter

    /// Configuration
    private let configuration: EchoConfiguration

    /// API key
    private let apiKey: String

    /// System message/instructions
    private let systemMessage: String?

    /// Turn manager for audio mode
    private var turnManager: TurnManager?

    /// Registered tools for function calling
    private let tools: [Tool]

    /// Registered MCP servers
    private let mcpServers: [MCPServer]

    /// Tool executor for centralized tool execution
    private let toolExecutor: ToolExecutor

    /// Optional audio capture factory for testing
    private let audioCaptureFactory: (@Sendable () async -> any AudioCaptureProtocol)?

    /// Optional audio playback factory for testing
    private let audioPlaybackFactory: (@Sendable () async -> any AudioPlaybackProtocol)?

    /// Task for observing audio level changes
    private var audioLevelObservationTask: Task<Void, Never>?
    
    // MARK: - Message Stream

    /// Stream of messages as they become available
    public var messages: AsyncStream<Message> {
        return AsyncStream { continuation in
            let queue = messageQueue
            Task {
                await queue.subscribe(continuation: continuation)
            }
        }
    }

    /// Get all messages in order
    public var allMessages: [Message] {
        get async {
            await messageQueue.getOrderedMessages()
        }
    }

    // MARK: - Initialization

    /// Creates a new conversation
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - mode: Initial mode (audio or text)
    ///   - configuration: Echo configuration
    ///   - systemMessage: Optional system instructions
    ///   - eventEmitter: Event emitter for publishing events
    ///   - tools: Registered tools for function calling
    ///   - mcpServers: Registered MCP servers
    ///   - toolExecutor: Tool executor for executing tools
    ///   - audioCaptureFactory: Optional factory for creating audio capture (for testing)
    ///   - audioPlaybackFactory: Optional factory for creating audio playback (for testing)
    init(
        apiKey: String,
        mode: EchoMode,
        configuration: EchoConfiguration,
        systemMessage: String? = nil,
        eventEmitter: EventEmitter,
        tools: [Tool] = [],
        mcpServers: [MCPServer] = [],
        toolExecutor: ToolExecutor,
        audioCaptureFactory: (@Sendable () async -> any AudioCaptureProtocol)? = nil,
        audioPlaybackFactory: (@Sendable () async -> any AudioPlaybackProtocol)? = nil
    ) async throws {
        self.id = UUID().uuidString
        self.mode = mode
        self.apiKey = apiKey
        self.configuration = configuration
        self.systemMessage = systemMessage
        self.eventEmitter = eventEmitter
        self.mcpServers = mcpServers
        self.tools = tools
        self.toolExecutor = toolExecutor
        self.messageQueue = MessageQueue(eventEmitter: eventEmitter)
        self.audioCaptureFactory = audioCaptureFactory
        self.audioPlaybackFactory = audioPlaybackFactory

        // Always initialize Realtime API - mode just determines output modality
        print("[RealtimeAPI] 🚀 Initializing session with mode: \(mode)")
        try await initializeRealtimeSession(audioEnabled: mode == .audio)
    }

    // MARK: - Session Initialization

    /// Initializes the Realtime API session with the specified audio state.
    ///
    /// This always uses the Realtime API, regardless of mode. The mode just determines:
    /// - Output modality (`["audio"]` vs `["text"]`)
    /// - Whether audio capture/playback is started
    ///
    /// - Parameter audioEnabled: Whether to enable audio capture and playback
    private func initializeRealtimeSession(audioEnabled: Bool) async throws {
        // Create turn manager if audio is enabled
        if audioEnabled {
            let turnMode: TurnManager.TurnMode
            switch configuration.turnDetection {
            case .automatic(let vad):
                turnMode = .automatic(vad)
            case .manual:
                turnMode = .manual(timeout: .seconds(30))
            case .disabled, .none:
                turnMode = .disabled
            }
            turnManager = TurnManager(mode: turnMode, eventEmitter: eventEmitter)
        } else {
            turnManager = nil
        }

        // Determine output modality and audio settings based on mode
        let outputModality: OutputModality = audioEnabled ? .audio : .text
        let startAudioAutomatically = audioEnabled
        let enableTranscription = audioEnabled && configuration.enableTranscription
        let turnDetection = audioEnabled ? configuration.turnDetection : nil
        
        print("[RealtimeAPI] 📡 Output modality: \(outputModality), audio auto-start: \(startAudioAutomatically)")

        // Create Realtime client configuration
        let realtimeConfig = RealtimeClientConfiguration(
            model: configuration.realtimeModel,
            voice: configuration.voice,
            speed: configuration.speed, 
            audioFormat: configuration.audioFormat,
            outputModality: outputModality,
            turnDetection: turnDetection,
            instructions: systemMessage,
            enableTranscription: enableTranscription,
            startAudioAutomatically: startAudioAutomatically,
            temperature: configuration.temperature,
            maxOutputTokens: configuration.maxTokens,
            defaultAudioOutput: configuration.defaultAudioOutput,
            echoProtection: audioEnabled ? configuration.echoProtection : nil,
            inputAudioConfiguration: audioEnabled ? configuration.inputAudioConfiguration : nil,
            idleTimeoutMs: configuration.idleTimeoutMs,
            transportType: configuration.transportType
        )

        // Create RealtimeClient with delegate (self) for direct calls
        let client = RealtimeClient(
            apiKey: apiKey,
            configuration: realtimeConfig,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers,
            turnManager: turnManager,
            toolExecutor: toolExecutor,
            delegate: self,
            audioCaptureFactory: audioCaptureFactory,
            audioPlaybackFactory: audioPlaybackFactory
        )

        // Connect and start session
        do {
            try await client.connect()
            realtimeClient = client
            
            // Start observing audio levels from events
            startAudioLevelObservation()
            print("[RealtimeAPI] ✅ Session initialized successfully")
        } catch {
            await client.disconnect()
            throw error
        }
    }
    
    /// Starts observing audio level events and updates observable properties
    private func startAudioLevelObservation() {
        audioLevelObservationTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.eventEmitter.events {
                switch event {
                case .inputLevelsChanged(let levels):
                    self.inputLevels = levels
                case .outputLevelsChanged(let levels):
                    self.outputLevels = levels
                default:
                    break
                }
            }
        }
    }

    // MARK: - RealtimeClientDelegate

    /// Called when a tool call is received from the model
    public nonisolated func realtimeClient(_ client: RealtimeClient, didReceiveToolCall call: ToolCall) async {
        // Tool calls are handled by the ToolExecutor in RealtimeClient
        // This delegate method is for custom handling if needed
    }

    /// Called when user speech is detected
    public nonisolated func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async {
        // Speech detection is handled by TurnManager
        // This is a fallback if TurnManager is not available
    }

    /// Called when user silence is detected
    public nonisolated func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async {
        // Silence detection is handled by TurnManager
        // This is a fallback if TurnManager is not available
    }

    /// Called when a user transcript is completed
    public nonisolated func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async {
        // Update the message queue with the transcript
        print("[Conversation] 📝 Received user transcript - itemId: \(itemId), text: '\(transcript)'")
        await messageQueue.updateTranscript(id: itemId, transcript: transcript)
    }

    /// Called when an assistant response is started
    public nonisolated func realtimeClient(_ client: RealtimeClient, didStartAssistantResponse itemId: String) async {
        // Create assistant message slot in the queue
        print("[Conversation] 🤖 Creating assistant message slot - itemId: \(itemId)")
        await messageQueue.enqueue(
            id: itemId,
            role: .assistant,
            text: nil,
            audioData: nil,
            transcriptStatus: .inProgress
        )
    }

    /// Called when an assistant response is completed
    public nonisolated func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async {
        // Finalize the assistant message in the queue
        print("[Conversation] ✅ Finalizing assistant message - itemId: \(itemId), text: '\(text)'")
        await messageQueue.updateTranscript(id: itemId, transcript: text)
    }

    /// Called when user audio buffer is committed
    public nonisolated func realtimeClient(_ client: RealtimeClient, didCommitAudioBuffer itemId: String) async {
        // Create user message slot in the queue
        print("[Conversation] 📦 Creating user message slot - itemId: \(itemId)")
        await messageQueue.enqueue(
            id: itemId,
            role: .user,
            text: nil,
            audioData: nil,
            transcriptStatus: .inProgress
        )
    }

    // MARK: - Sending Messages

    /// Sends a text message via the Realtime API.
    ///
    /// The message is sent as a text input to the Realtime API. The response
    /// will be either audio+transcript or text-only depending on the current
    /// output modality.
    ///
    /// - Parameter text: The message text
    /// - Returns: nil (responses come through events)
    /// - Throws: EchoError if sending fails
    @discardableResult
    public func send(_ text: String) async throws -> Message? {
        // Always use Realtime API
        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized")
        }
        
        print("[RealtimeAPI] 📤 Sending text message: \"\(text.prefix(50))...\"")

        // Create conversation item with text
        let itemDict: [String: Any] = [
            "type": "message",
            "role": "user",
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ]
            ]
        ]

        let sendableItem = try SendableJSON.from(dictionary: itemDict)
        try await client.send(.conversationItemCreate(item: sendableItem, previousItemId: nil))
        
        // Always trigger response for text input (no VAD involved)
        // In text mode or when typing in audio mode, we need to explicitly request a response
        try await client.send(.responseCreate(response: nil))
        
        // Add message to queue to maintain unified history
        _ = await messageQueue.enqueue(
            role: .user,
            text: text,
            audioData: nil,
            transcriptStatus: .completed
        )
        
        // Responses come through events
        return nil
    }

    /// Sends a text message via the Realtime API.
    ///
    /// This is an alias for `send(_:)` for backwards compatibility.
    /// All responses come through events, not return values.
    ///
    /// - Note: The Realtime API does not support structured outputs (responseFormat).
    ///   If you need structured outputs, use the ResponsesClient directly.
    ///
    /// - Parameters:
    ///   - text: The message text
    ///   - responseFormat: Ignored. Realtime API does not support structured outputs.
    /// - Returns: nil (responses come through events)
    /// - Throws: EchoError if sending fails
    @discardableResult
    public func sendMessage(
        _ text: String,
        responseFormat: ResponseFormat? = nil
    ) async throws -> Message? {
        if responseFormat != nil {
            print("[RealtimeAPI] ⚠️ Warning: responseFormat is not supported by Realtime API and will be ignored")
        }
        return try await send(text)
    }

    // MARK: - Mode Switching
    
    /// Whether audio is currently enabled for this conversation.
    ///
    /// When audio is enabled, the microphone captures user speech and responses
    /// are played through the speaker. When disabled, the user types messages
    /// and responses are text-only (no audio generation on the server).
    ///
    /// This property reflects the current output modality of the Realtime session.
    public var isAudioEnabled: Bool {
        get async {
            guard let client = realtimeClient else { return false }
            return await client.currentOutputModality == .audio
        }
    }
    
    /// Enables or disables audio for this conversation.
    ///
    /// This method provides a cost-effective way to switch between voice and text
    /// interaction within the same session, without losing conversation context.
    ///
    /// **When enabling audio (`true`):**
    /// - Server output modality changes to audio (responses include audio + transcript)
    /// - Audio capture (microphone) starts
    /// - Audio playback (speaker) starts
    ///
    /// **When disabling audio (`false`):**
    /// - Server output modality changes to text (responses are text-only, no audio generation)
    /// - Audio capture stops
    /// - Audio playback stops
    ///
    /// - Parameter enabled: Whether to enable audio
    /// - Throws: EchoError if the operation fails
    ///
    /// - Note: This keeps the same Realtime API session, preserving all conversation
    ///   context without resending history. Much more cost-effective than switching APIs.
    public func setAudioEnabled(_ enabled: Bool) async throws {
        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized")
        }
        
        let currentModality = await client.currentOutputModality
        let targetModality: OutputModality = enabled ? .audio : .text
        
        // Early exit if already in the desired state
        guard currentModality != targetModality else { return }
        
        await eventEmitter.emit(.modeSwitching(from: enabled ? .text : .audio, to: enabled ? .audio : .text))
        
        // Update server-side output modality (no history resend!)
        print("[RealtimeAPI] 📤 Updating output modality to: \(targetModality)")
        try await client.updateOutputModality(targetModality)
        
        // Start or stop audio engine based on the new state
        if enabled {
            print("[RealtimeAPI] 🎙️ Starting audio capture and playback")
            try await client.startAudio()
            mode = .audio
        } else {
            print("[RealtimeAPI] 🔇 Stopping audio capture and playback")
            await client.stopAudio()
            mode = .text
        }
        
        print("[RealtimeAPI] ✅ Mode switched to \(mode) (context preserved)")
        await eventEmitter.emit(.modeSwitched(to: mode))
    }

    /// Switches between audio and text mode within the same session.
    ///
    /// This method toggles the output modality of the Realtime API:
    /// - **Audio mode**: Responses include audio + transcript, microphone active
    /// - **Text mode**: Responses are text-only, no audio generation
    ///
    /// **Key benefit**: No history resend. Context is preserved within the same
    /// session, making this extremely cost-effective compared to switching APIs.
    ///
    /// - Parameter newMode: The mode to switch to
    /// - Throws: EchoError if switching fails
    public func switchMode(to newMode: EchoMode) async throws {
        guard mode != newMode else { return }
        print("[RealtimeAPI] 🔄 Switching mode to \(newMode) (context preserved)")
        try await setAudioEnabled(newMode == .audio)
    }

    // MARK: - Audio Control

    /// Mutes/unmutes audio input
    /// - Parameter muted: Whether to mute audio
    /// - Throws: EchoError if not in audio mode
    public func setMuted(_ muted: Bool) async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot mute/unmute in text mode")
        }

        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized")
        }

        try await client.setMuted(muted)
    }

    /// Sets the audio output device
    /// - Parameter device: The audio output device to use
    /// - Throws: EchoError if not in audio mode or audio is not active
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot set audio output in text mode")
        }

        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized")
        }

        try await client.setAudioOutput(device: device)
    }
    
    /// List of available audio output devices
    public var availableAudioOutputDevices: [AudioOutputDeviceType] {
        get async {
            guard mode == .audio, let client = realtimeClient else {
                return []
            }
            return await client.availableAudioOutputDevices
        }
    }
    
    /// Current active audio output device
    public var currentAudioOutput: AudioOutputDeviceType {
        get async {
            guard mode == .audio, let client = realtimeClient else {
                return .systemDefault
            }
            return await client.currentAudioOutput
        }
    }
    
    /// Installs an audio tap on the playback engine's main mixer node for external monitoring
    /// - Parameters:
    ///   - bufferSize: The buffer size for the tap (default: 1024)
    ///   - format: The audio format for the tap (nil uses the output format)
    ///   - handler: The closure called with audio buffer data
    /// - Note: This method safely installs a tap without exposing the AVAudioEngine directly,
    ///         avoiding Sendable constraints in Swift 6 strict concurrency.
    /// - Warning: Only one tap can be installed at a time. Call `removeAudioTap()` before installing a new one.
    public func installAudioTap(
        bufferSize: UInt32 = 1024,
        format: AVAudioFormat? = nil,
        handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) async throws {
        guard mode == .audio, let client = realtimeClient else {
            throw EchoError.invalidMode("Cannot install audio tap when not in audio mode")
        }
        try await client.installAudioTap(bufferSize: bufferSize, format: format, handler: handler)
    }
    
    /// Removes the audio tap from the playback engine's main mixer node
    public func removeAudioTap() async {
        guard mode == .audio, let client = realtimeClient else {
            return
        }
        await client.removeAudioTap()
    }

    /// Manually ends the user's turn (for manual turn mode)
    /// - Throws: EchoError if not in audio mode
    public func endUserTurn() async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot end turn in text mode")
        }

        // Only commit audio buffer in manual mode
        guard case .manual = configuration.turnDetection else {
            return
        }

        await turnManager?.endUserTurn()

        // Commit audio buffer and trigger response (manual mode only)
        try await realtimeClient?.send(.inputAudioBufferCommit)
        try await realtimeClient?.send(.responseCreate(response: nil))
    }

    /// Interrupts the assistant (stops current response)
    /// - Throws: EchoError if not in audio mode
    public func interruptAssistant() async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot interrupt in text mode")
        }

        await turnManager?.interruptAssistant()

        // Cancel current response
        try await realtimeClient?.send(.responseCancel)
    }

    /// Updates VAD (Voice Activity Detection) settings at runtime
    /// - Parameters:
    ///   - threshold: Detection threshold (0.0-1.0, higher = less sensitive)
    ///   - silenceDuration: Duration of silence before turn ends
    ///   - prefixPadding: Audio padding before speech detection
    /// - Throws: EchoError if not in audio mode or if VAD is not enabled
    public func updateVAD(
        threshold: Double? = nil,
        silenceDuration: Duration? = nil,
        prefixPadding: Duration? = nil
    ) async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot update VAD in text mode")
        }

        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized")
        }

        guard case .automatic(let currentVAD) = configuration.turnDetection else {
            throw EchoError.invalidMode("VAD updates only supported in automatic turn mode")
        }

        // Build updated VAD configuration
        let updatedVAD = VADConfiguration(
            type: currentVAD.type,
            eagerness: currentVAD.eagerness,
            threshold: threshold ?? currentVAD.threshold,
            silenceDurationMs: silenceDuration.map { Int($0.components.seconds * 1000) } ?? currentVAD.silenceDurationMs,
            prefixPaddingMs: prefixPadding.map { Int($0.components.seconds * 1000) } ?? currentVAD.prefixPaddingMs,
            interruptResponse: currentVAD.interruptResponse,
            createResponse: currentVAD.createResponse
        )

        // Create session update with new VAD settings
        let turnDetectionDict = updatedVAD.toRealtimeFormat()
        let sessionUpdate: [String: Any] = [
            "turn_detection": turnDetectionDict
        ]

        let sessionJSON = try SendableJSON.from(dictionary: sessionUpdate)
        try await client.send(.sessionUpdate(session: sessionJSON))
    }

    // MARK: - Send With Response (Convenience Method)
    
    /// Sends a text message and waits for the complete response
    /// - Parameter text: The message text
    /// - Returns: The assistant's response message
    /// - Throws: EchoError if sending fails or not in text mode
    public func sendWithResponse(_ text: String) async throws -> Message? {
        guard mode == .text else {
            throw EchoError.invalidMode("sendWithResponse only available in text mode")
        }
        
        return try await sendMessage(text)
    }
    
    // MARK: - Cleanup

    /// Disconnects and cleans up resources
    public func disconnect() async {
        // Cancel audio level observation
        audioLevelObservationTask?.cancel()
        audioLevelObservationTask = nil
        
        await realtimeClient?.disconnect()
        realtimeClient = nil
        turnManager = nil
    }
}
