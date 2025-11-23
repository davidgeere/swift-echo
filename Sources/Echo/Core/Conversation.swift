// Conversation.swift
// Echo - Core  
// Manages a single conversation with mode switching support

@preconcurrency import Foundation
import Observation

/// Manages a single conversation with seamless mode switching between audio and text
@MainActor
@Observable
public class Conversation {
    // MARK: - Properties

    /// Unique conversation ID
    public let id: String

    /// Current conversation mode
    public private(set) var mode: EchoMode

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

    /// Optional audio capture factory for testing
    private let audioCaptureFactory: (@Sendable () async -> any AudioCaptureProtocol)?

    /// Optional audio playback factory for testing
    private let audioPlaybackFactory: (@Sendable () async -> any AudioPlaybackProtocol)?

    
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
        // CRITICAL FIX: Support manual mode instead of coercing to .disabled
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
        // CRITICAL FIX: Pass systemMessage as instructions instead of nil
        let realtimeConfig = RealtimeClientConfiguration(
            model: configuration.realtimeModel,
            voice: configuration.voice,
            audioFormat: configuration.audioFormat,
            turnDetection: configuration.turnDetection,
            instructions: systemMessage,  // ✅ FIXED: Use actual systemMessage
            enableTranscription: configuration.enableTranscription,
            startAudioAutomatically: true,
            temperature: configuration.temperature,
            maxOutputTokens: configuration.maxTokens
        )

        // CRITICAL FIX: Pass TurnManager to RealtimeClient for event routing
        // Also pass audio factories for dependency injection (testing)
        let client = RealtimeClient(
            apiKey: apiKey,
            configuration: realtimeConfig,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers,
            turnManager: turnManager,  // ✅ Wire TurnManager into event flow
            audioCaptureFactory: audioCaptureFactory,  // ✅ Enable mock audio for testing
            audioPlaybackFactory: audioPlaybackFactory  // ✅ Enable mock audio for testing
        )

        // Set up event listeners for MessageQueue population
        setupAudioModeEventListeners()

        // Connect and start session - this may throw
        do {
            try await client.connect()
            // Only assign if connection succeeds
            realtimeClient = client
        } catch {
            // Connection failed - clean up and propagate error
            await client.disconnect()
            throw error
        }
    }

    private func initializeTextMode() async throws {
        // Create Responses client - lightweight, no connection needed
        let client = ResponsesClient(
            apiKey: apiKey,
            eventEmitter: eventEmitter
        )
        responsesClient = client

        // Set up event listeners for text mode
        setupTextModeEventListeners()
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

            // CRITICAL FIX: Wait for stream completion using continuation
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
                                        // This can happen with certain prompts that trigger extended reasoning
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
                
                #if DEBUG
                print("[Conversation] JSON mode: Response output count: \(response.output.count)")
                #endif
                if !response.output.isEmpty {
                    #if DEBUG
                print("[Conversation] JSON mode: First output item: \(response.output[0])")
                #endif
                }
                
                // Try to extract text from the response
                // In JSON mode, we might not get a message with text but we still get content
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
                    #if DEBUG
                    print("[Conversation] JSON mode: Got text: \(firstItem)")
                    #endif
                    let messageId = await messageQueue.enqueue(
                        role: .assistant,
                        text: firstItem,
                        audioData: nil,
                        transcriptStatus: .notApplicable
                    )
                    #if DEBUG
                    print("[Conversation] JSON mode: Enqueued with ID: \(messageId)")
                    #endif
                    
                    // Return the created message
                    let message = await messageQueue.getMessage(byId: messageId)
                    #if DEBUG
                    print("[Conversation] JSON mode: Retrieved message: \(String(describing: message))")
                    #endif
                    return message
                }
                #if DEBUG
                print("[Conversation] JSON mode: No text in response")
                #endif
                return nil
            } else {
                // Streaming mode (default behavior)
                // CRITICAL FIX: Wait for stream completion using continuation
                #if DEBUG
                print("[Conversation] Starting streaming response...")
                #endif
                
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
                                        // Log error in debug builds
                                        #if DEBUG
                                        print("[Conversation] Stream failed with error: \(error)")
                                        #endif
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
                                            // This can happen with certain prompts that trigger extended reasoning
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
                                #if DEBUG
                                print("[Conversation] Stream error: \(error)")
                                #endif
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
    /// This must be nonisolated to avoid MainActor isolation conflicts
    /// We isolate the stream processing to the client actor to avoid Sendable issues
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
        // Process the stream isolated to the client actor
        // This avoids the non-Sendable AsyncThrowingStream crossing actor boundaries
        await client.withStreamResponse(
            model: model,
            input: history,
            instructions: instructions,
            tools: tools,
            temperature: temperature,
            maxOutputTokens: maxOutputTokens
        ) { stream in
            // Process stream events
            var assistantText = ""
            do {
                for try await event in stream {
                    switch event {
                    case .responseDelta(let delta):
                        // Accumulate text
                        assistantText += delta
                    case .responseDone(_):
                        // Add complete message to queue
                        if !assistantText.isEmpty {
                            await messageQueue.enqueue(
                                role: .assistant,
                                text: assistantText,
                                audioData: nil,
                                transcriptStatus: .notApplicable
                            )
                        }
                    default:
                        // Other events are handled elsewhere
                        break
                    }
                }
            } catch {
                // Stream error - emit error event
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
        // 1. Get all messages from queue (includes transcripts from audio)
        let _ = await messageQueue.getOrderedMessages()

        // 2. Disconnect Realtime WebSocket
        await realtimeClient?.disconnect()
        realtimeClient = nil
        turnManager = nil

        // 3. Initialize Responses client
        try await initializeTextMode()

        // Context is already preserved in MessageQueue as text transcripts
    }

    private func transitionTextToAudio() async throws {
        // 1. Get conversation history
        let messages = await messageQueue.getOrderedMessages()

        // 2. Initialize Realtime WebSocket FIRST (before destroying responses client)
        try await initializeAudioMode()

        // 3. Clean up Responses client only AFTER successful audio initialization
        responsesClient = nil

        // 4. Inject history into Realtime API
        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized after initialization")
        }

        // Send each message as a conversation item
        // CRITICAL: Realtime API expects "input_text" for user messages and "text" for assistant messages
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

        // Ready for audio interaction with full context
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

    /// Sets the audio output routing
    /// - Parameter useSpeaker: If true, routes to built-in speaker (bypasses Bluetooth);
    ///                         if false, removes override and allows system to choose route
    ///                         (will use Bluetooth if connected, otherwise earpiece)
    /// - Throws: EchoError if not in audio mode or audio is not active
    public func setSpeakerRouting(useSpeaker: Bool) async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot set speaker routing in text mode")
        }

        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized")
        }

        try await client.setSpeakerRouting(useSpeaker: useSpeaker)
    }
    
    /// Current speaker routing state
    /// Returns true if speaker is forced, false if using default routing (Bluetooth/earpiece), nil if not set
    public var speakerRouting: Bool? {
        get async {
            guard mode == .audio, let client = realtimeClient else {
                return nil
            }
            return await client.speakerRouting
        }
    }
    
    /// Whether Bluetooth is currently connected for audio output
    public var isBluetoothConnected: Bool {
        get async {
            guard mode == .audio, let client = realtimeClient else {
                return false
            }
            return await client.isBluetoothConnected
        }
    }

    /// Manually ends the user's turn (for manual turn mode)
    /// - Throws: EchoError if not in audio mode
    public func endUserTurn() async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot end turn in text mode")
        }

        // CRITICAL FIX: Only commit audio buffer in manual mode
        // In automatic mode, VAD drives the commits - manual calls should be no-ops
        guard case .manual = configuration.turnDetection else {
            // In automatic mode, don't manually commit - VAD handles it
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

    // MARK: - Event Listeners

    /// Sets up event listeners for audio mode MessageQueue population
    private func setupAudioModeEventListeners() {
        let queue = messageQueue
        let emitter = eventEmitter

        // Listen for user audio buffer committed - creates message slot
        Task {
            await emitter.when(.userAudioBufferCommitted) { event in
                if case .userAudioBufferCommitted(let itemId) = event {
                    print("[Conversation] 📦 Creating user message slot - itemId: \(itemId)")
                    await queue.enqueue(
                        id: itemId,
                        role: .user,
                        text: nil,
                        audioData: nil,
                        transcriptStatus: .inProgress
                    )
                }
            }
        }

        // Listen for user transcription completed - updates transcript
        Task {
            await emitter.when(.userTranscriptionCompleted) { event in
                if case .userTranscriptionCompleted(let transcript, let itemId) = event {
                    print("[Conversation] 📝 Updating user transcript - itemId: \(itemId), text: '\(transcript)'")
                    await queue.updateTranscript(id: itemId, transcript: transcript)
                }
            }
        }

        // Listen for assistant response created - creates message slot
        Task {
            await emitter.when(.assistantResponseCreated) { event in
                if case .assistantResponseCreated(let itemId) = event {
                    print("[Conversation] 🤖 Creating assistant message slot - itemId: \(itemId)")
                    await queue.enqueue(
                        id: itemId,
                        role: .assistant,
                        text: nil,
                        audioData: nil,
                        transcriptStatus: .inProgress
                    )
                }
            }
        }

        // Listen for assistant response done - updates transcript
        Task {
            await emitter.when(.assistantResponseDone) { event in
                if case .assistantResponseDone(let itemId, let text) = event {
                    print("[Conversation] ✅ Finalizing assistant message - itemId: \(itemId), text: '\(text)'")
                    await queue.updateTranscript(id: itemId, transcript: text)
                }
            }
        }
    }

    /// Sets up event listeners for text mode MessageQueue population
    private func setupTextModeEventListeners() {
        // In text mode, messages are added directly to the queue by ResponsesClient
        // No need for event listeners - they would cause duplicates
        // The ResponsesClient should directly add messages to MessageQueue
    }

    // MARK: - Send With Response (Convenience Method)
    
    /// Sends a text message and waits for the complete response
    /// This is a convenience method for text mode that ensures the response is returned
    /// - Parameter text: The message text
    /// - Returns: The assistant's response message
    /// - Throws: EchoError if sending fails or not in text mode
    public func sendWithResponse(_ text: String) async throws -> Message? {
        guard mode == .text else {
            throw EchoError.invalidMode("sendWithResponse only available in text mode")
        }
        
        // For now, just call sendMessage which works properly
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
}
