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

    /// Realtime client for audio mode
    private var realtimeClient: RealtimeClient?

    /// Responses client for text mode
    private var responsesClient: ResponsesClient?

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

        // Initialize the appropriate client based on mode
        switch mode {
        case .audio:
            try await initializeAudioMode()
        case .text:
            try await initializeTextMode()
        }
    }

    // MARK: - Mode Initialization

    private func initializeAudioMode() async throws {
        // Create turn manager with proper mode handling
        let turnMode: TurnManager.TurnMode
        switch configuration.turnDetection {
        case .automatic(let vad):
            turnMode = .automatic(vad)
        case .manual:
            // Manual mode with 30-second timeout fallback
            turnMode = .manual(timeout: .seconds(30))
        case .disabled, .none:
            turnMode = .disabled
        }
        turnManager = TurnManager(mode: turnMode, eventEmitter: eventEmitter)

        // Create Realtime client configuration with systemMessage
        let realtimeConfig = RealtimeClientConfiguration(
            model: configuration.realtimeModel,
            voice: configuration.voice,
            audioFormat: configuration.audioFormat,
            turnDetection: configuration.turnDetection,
            instructions: systemMessage,
            enableTranscription: configuration.enableTranscription,
            startAudioAutomatically: true,
            temperature: configuration.temperature,
            maxOutputTokens: configuration.maxTokens
        )

        // Create RealtimeClient with delegate (self) for direct calls
        // No more event listener Tasks needed!
        let client = RealtimeClient(
            apiKey: apiKey,
            configuration: realtimeConfig,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers,
            turnManager: turnManager,
            toolExecutor: toolExecutor,
            delegate: self,  // Wire self as delegate for direct calls
            audioCaptureFactory: audioCaptureFactory,
            audioPlaybackFactory: audioPlaybackFactory
        )

        // Connect and start session - this may throw
        do {
            try await client.connect()
            // Only assign if connection succeeds
            realtimeClient = client
            
            // Start observing audio levels from events
            startAudioLevelObservation()
        } catch {
            // Connection failed - clean up and propagate error
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

    private func initializeTextMode() async throws {
        // Create Responses client - lightweight, no connection needed
        let client = ResponsesClient(
            apiKey: apiKey,
            eventEmitter: eventEmitter
        )
        responsesClient = client

        // No event listeners needed in text mode
        // Messages are added directly to the queue by ResponsesClient
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

    /// Sends a text message and returns the response (in text mode)
    /// - Parameter text: The message text
    /// - Returns: The assistant's response message (in text mode only)
    /// - Throws: EchoError if sending fails
    public func send(_ text: String) async throws -> Message? {
        switch mode {
        case .audio:
            // In audio mode, send as text input (will be synthesized to speech)
            guard let client = realtimeClient else {
                throw EchoError.clientNotInitialized("Realtime client not initialized")
            }

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
            
            // Only manually trigger response if NOT using automatic turn detection
            // In automatic mode, VAD will trigger the response when it detects silence
            if case .manual = configuration.turnDetection {
                try await client.send(.responseCreate(response: nil))
            }
            
            // Add message to queue to maintain unified history
            _ = await messageQueue.enqueue(
                role: .user,
                text: text,
                audioData: nil,
                transcriptStatus: .completed
            )
            
            // Audio mode is streaming, response will come through events
            return nil

        case .text:
            // In text mode, send to Responses API and await response
            guard let client = responsesClient else {
                throw EchoError.clientNotInitialized("Responses client not initialized")
            }

            // Add message to queue
            _ = await messageQueue.enqueue(
                role: .user,
                text: text,
                audioData: nil,
                transcriptStatus: .notApplicable
            )

            // Get conversation history
            let history = await messageQueue.getOrderedMessages()

            // Send to Responses API with streaming
            let responsesModel = configuration.responsesModel

            // Convert tools and MCP servers to ResponsesTool format
            var allResponsesTools: [ResponsesTool] = []
            allResponsesTools.append(contentsOf: tools.map { $0.toResponsesTool() })
            allResponsesTools.append(contentsOf: mcpServers.map { $0.toResponsesTool() })

            // Wait for stream completion using continuation
            let assistantMessage = await withCheckedContinuation { (continuation: CheckedContinuation<Message?, Never>) in
                Task {
                    await client.withStreamResponse(
                        model: responsesModel,
                        input: history,
                        instructions: systemMessage,
                        tools: allResponsesTools,
                        temperature: configuration.temperature,
                        maxOutputTokens: configuration.maxTokens,
                        reasoningEffort: configuration.reasoningEffort
                    ) { stream in
                        var assistantText = ""
                        var finalMessageId: String? = nil
                        
                        do {
                            for try await event in stream {
                                switch event {
                                case .responseDelta(let delta):
                                    // Accumulate text
                                    assistantText += delta
                                    
                                case .responseDone(let response):
                                    // Extract final text if available
                                    if let firstText = response.firstText, !firstText.isEmpty {
                                        assistantText = firstText
                                    }
                                    
                                case .responseFailed(let error):
                                    await eventEmitter.emit(.error(error: EchoError.invalidResponse(error)))
                                    
                                case .raw(let type, let data):
                                    // Handle raw events that might contain text
                                    if type == "response.output_text.done" {
                                        // Extract text from the raw event
                                        if let text = data["text"]?.value as? String {
                                            assistantText = text
                                        }
                                    } else if type == "response.output_item.done" {
                                        // Alternative format for text completion
                                        if let item = data["item"]?.value as? [String: Any],
                                           let contentArray = item["content"] as? [[String: Any]] {
                                            for content in contentArray {
                                                if content["type"] as? String == "text",
                                                   let text = content["text"] as? String {
                                                    assistantText = text
                                                    break
                                                }
                                            }
                                        }
                                    } else if type == "response.incomplete" {
                                        // Handle incomplete responses (e.g., reasoning-only responses)
                                        await eventEmitter.emit(.error(error: EchoError.invalidResponse(
                                            "Response was incomplete - the model returned only reasoning without a text response. Try rephrasing your question or adjusting reasoning effort."
                                        )))
                                    }
                                    
                                default:
                                    // Handle other events
                                    break
                                }
                            }
                            
                            // After stream completes, enqueue the message
                            if !assistantText.isEmpty {
                                finalMessageId = await messageQueue.enqueue(
                                    role: .assistant,
                                    text: assistantText,
                                    audioData: nil,
                                    transcriptStatus: .notApplicable
                                )
                            }
                        } catch {
                            await eventEmitter.emit(.error(error: error))
                        }
                        
                        // Resume with the final message
                        if let messageId = finalMessageId {
                            let message = await messageQueue.getMessage(byId: messageId)
                            continuation.resume(returning: message)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
            
            return assistantMessage
        }
    }

    /// Sends a message with optional response format (for structured outputs)
    /// - Parameters:
    ///   - text: The message text
    ///   - responseFormat: Optional response format for structured outputs (text mode only)
    /// - Returns: The assistant's response message (for non-streaming use cases)
    /// - Throws: EchoError if sending fails
    public func sendMessage(
        _ text: String,
        responseFormat: ResponseFormat? = nil
    ) async throws -> Message? {
        switch mode {
        case .audio:
            // In audio mode, responseFormat is not applicable
            if responseFormat != nil {
                print("[Conversation] Warning: responseFormat is ignored in audio mode")
            }
            _ = try await send(text)
            return nil  // Audio mode is always streaming
            
        case .text:
            // In text mode, send to Responses API with optional format
            guard let client = responsesClient else {
                throw EchoError.clientNotInitialized("Responses client not initialized")
            }
            
            // Add user message to queue
            _ = await messageQueue.enqueue(
                role: .user,
                text: text,
                audioData: nil,
                transcriptStatus: .notApplicable
            )
            
            // Get conversation history
            let history = await messageQueue.getOrderedMessages()
            
            // Convert tools and MCP servers to ResponsesTool format
            var allResponsesTools: [ResponsesTool] = []
            allResponsesTools.append(contentsOf: tools.map { $0.toResponsesTool() })
            allResponsesTools.append(contentsOf: mcpServers.map { $0.toResponsesTool() })
            
            // If responseFormat is provided and JSON mode requested, use non-streaming
            if let format = responseFormat {
                // Non-streaming for structured outputs
                let response = try await client.createResponseWithFormat(
                    model: configuration.responsesModel,
                    input: history,
                    instructions: systemMessage,
                    tools: allResponsesTools,
                    temperature: configuration.temperature,
                    maxOutputTokens: configuration.maxTokens,
                    responseFormat: format
                )
                
                // Try to extract text from the response
                var responseText: String? = response.firstText
                
                // If no text found via firstText, try to extract from output items
                if responseText == nil && !response.output.isEmpty {
                    // Look through output items for message content
                    for outputItem in response.output {
                        if case .message(let message) = outputItem {
                            // Extract text from message content parts
                            for contentPart in message.content {
                                if case .text(let text) = contentPart {
                                    responseText = text
                                    break
                                }
                            }
                            if responseText != nil {
                                break
                            }
                        }
                    }
                }
                
                // Extract and enqueue response message
                if let firstItem = responseText {
                    let messageId = await messageQueue.enqueue(
                        role: .assistant,
                        text: firstItem,
                        audioData: nil,
                        transcriptStatus: .notApplicable
                    )
                    
                    // Return the created message
                    let message = await messageQueue.getMessage(byId: messageId)
                    return message
                }
                return nil
            } else {
                // Streaming mode (default behavior)
                let assistantMessage = await withCheckedContinuation { (continuation: CheckedContinuation<Message?, Never>) in
                    Task {
                        await client.withStreamResponse(
                            model: configuration.responsesModel,
                            input: history,
                            instructions: systemMessage,
                            tools: allResponsesTools,
                            temperature: configuration.temperature,
                            maxOutputTokens: configuration.maxTokens,
                            reasoningEffort: configuration.reasoningEffort
                        ) { stream in
                            var assistantText = ""
                            var finalMessageId: String? = nil
                            
                            do {
                                for try await event in stream {
                                    switch event {
                                    case .responseDelta(let delta):
                                        // Accumulate text
                                        assistantText += delta
                                        
                                    case .responseDone(let response):
                                        // Extract final text if available
                                        if let firstText = response.firstText, !firstText.isEmpty {
                                            assistantText = firstText
                                        }
                                        
                                    case .responseFailed(let error):
                                        await eventEmitter.emit(.error(error: EchoError.invalidResponse(error)))
                                        
                                    case .raw(let type, let data):
                                        // Handle raw events that might contain text
                                        if type == "response.output_text.done" {
                                            // Extract text from the raw event
                                            if let text = data["text"]?.value as? String {
                                                assistantText = text
                                            }
                                        } else if type == "response.output_item.done" {
                                            // Alternative format for text completion
                                            if let item = data["item"]?.value as? [String: Any],
                                               let contentArray = item["content"] as? [[String: Any]] {
                                                for content in contentArray {
                                                    if content["type"] as? String == "text",
                                                       let text = content["text"] as? String {
                                                        assistantText = text
                                                        break
                                                    }
                                                }
                                            }
                                        } else if type == "response.incomplete" {
                                            // Handle incomplete responses
                                            await eventEmitter.emit(.error(error: EchoError.invalidResponse(
                                                "Response was incomplete - the model returned only reasoning without a text response. Try rephrasing your question."
                                            )))
                                        }
                                        
                                    default:
                                        // Handle other events
                                        break
                                    }
                                }
                                
                                // After stream completes, enqueue the message
                                if !assistantText.isEmpty {
                                    finalMessageId = await messageQueue.enqueue(
                                        role: .assistant,
                                        text: assistantText,
                                        audioData: nil,
                                        transcriptStatus: .notApplicable
                                    )
                                }
                            } catch {
                                await eventEmitter.emit(.error(error: error))
                            }
                            
                            // Resume with the final message
                            if let messageId = finalMessageId {
                                let message = await messageQueue.getMessage(byId: messageId)
                                continuation.resume(returning: message)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                }
                
                return assistantMessage
            }
        }
    }
    
    // MARK: - Stream Processing

    /// Processes the response stream from Responses API
    nonisolated private static func processResponseStream(
        client: ResponsesClient,
        model: ResponsesModel,
        history: [Message],
        instructions: String?,
        tools: [ResponsesTool],
        emitter: EventEmitter,
        messageQueue: MessageQueue,
        temperature: Double,
        maxOutputTokens: Int?,
        responseFormat: ResponseFormat? = nil
    ) async {
        await client.withStreamResponse(
            model: model,
            input: history,
            instructions: instructions,
            tools: tools,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens
        ) { stream in
            var assistantText = ""
            do {
                for try await event in stream {
                    switch event {
                    case .responseDelta(let delta):
                        assistantText += delta
                    case .responseDone(_):
                        if !assistantText.isEmpty {
                            await messageQueue.enqueue(
                                role: .assistant,
                                text: assistantText,
                                audioData: nil,
                                transcriptStatus: .notApplicable
                            )
                        }
                    default:
                        break
                    }
                }
            } catch {
                await emitter.emit(.error(error: error))
            }
        }
    }

    // MARK: - Mode Switching

    /// Switches to a different mode
    /// - Parameter newMode: The mode to switch to
    /// - Throws: EchoError if switching fails
    public func switchMode(to newMode: EchoMode) async throws {
        guard mode != newMode else { return }

        await eventEmitter.emit(.modeSwitching(from: mode, to: newMode))

        switch (mode, newMode) {
        case (.audio, .text):
            try await transitionAudioToText()
        case (.text, .audio):
            try await transitionTextToAudio()
        default:
            break
        }

        mode = newMode
        await eventEmitter.emit(.modeSwitched(to: newMode))
    }

    private func transitionAudioToText() async throws {
        // Disconnect Realtime WebSocket
        await realtimeClient?.disconnect()
        realtimeClient = nil
        turnManager = nil

        // Initialize Responses client
        try await initializeTextMode()
    }

    private func transitionTextToAudio() async throws {
        // Get conversation history
        let messages = await messageQueue.getOrderedMessages()

        // Initialize Realtime WebSocket FIRST (before destroying responses client)
        try await initializeAudioMode()

        // Clean up Responses client only AFTER successful audio initialization
        responsesClient = nil

        // Inject history into Realtime API
        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized after initialization")
        }
        
        // Send each message as a conversation item
        for message in messages {
            let contentType = message.role == .user ? "input_text" : "text"
            let itemDict: [String: Any] = [
                "type": "message",
                "role": message.role.rawValue,
                "content": [
                    [
                        "type": contentType,
                        "text": message.text
                    ]
                ]
            ]

            let sendableItem = try SendableJSON.from(dictionary: itemDict)
            try await client.send(.conversationItemCreate(item: sendableItem, previousItemId: nil))
        }
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
            threshold: threshold ?? currentVAD.threshold,
            silenceDurationMs: silenceDuration.map { Int($0.components.seconds * 1000) } ?? currentVAD.silenceDurationMs,
            prefixPaddingMs: prefixPadding.map { Int($0.components.seconds * 1000) } ?? currentVAD.prefixPaddingMs,
            enableInterruption: currentVAD.enableInterruption
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
        await realtimeClient?.disconnect()
        realtimeClient = nil
        responsesClient = nil
        turnManager = nil
    }
    
    deinit {
        audioLevelObservationTask?.cancel()
    }
}
