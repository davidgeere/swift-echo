// Conversation.swift
// Echo - Core  
// Manages a single conversation with mode switching support

@preconcurrency import Foundation
import Observation

/// Manages a single conversation with seamless mode switching between audio and text
@MainActor
@Observable
public class Conversation: RealtimeClientDelegate, TurnManagerDelegate {
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
    
    /// Tool executor for handling tool calls
    private let toolExecutor: ToolExecutor?

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
    ///   - toolExecutor: Optional tool executor for handling tool calls
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
        toolExecutor: ToolExecutor? = nil,
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
            turnMode = .manual(timeout: .seconds(30))
        case .disabled, .none:
            turnMode = .disabled
        }
        
        // Create turn manager with self as delegate
        let tm = TurnManager(mode: turnMode, eventEmitter: eventEmitter)
        await tm.setDelegate(self)
        turnManager = tm

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

        // Create RealtimeClient with direct references (no event listener Tasks)
        let client = RealtimeClient(
            apiKey: apiKey,
            configuration: realtimeConfig,
            eventEmitter: eventEmitter,
            tools: tools,
            mcpServers: mcpServers,
            turnManager: turnManager,
            toolExecutor: toolExecutor,
            delegate: self,  // Direct delegate instead of event listeners
            audioCaptureFactory: audioCaptureFactory,
            audioPlaybackFactory: audioPlaybackFactory
        )

        // NO event listener setup - using delegate pattern instead

        // Connect and start session
        do {
            try await client.connect()
            realtimeClient = client
        } catch {
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
        // NO event listener setup needed for text mode
    }

    // MARK: - RealtimeClientDelegate Implementation

    nonisolated public func realtimeClient(_ client: RealtimeClient, didReceiveToolCall call: ToolCall) async {
        // Tool calls are handled by ToolExecutor directly in RealtimeClient
        // This is only called if no executor is set
    }

    nonisolated public func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async {
        // Speech events are handled by TurnManager directly
    }

    nonisolated public func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async {
        // Silence events are handled by TurnManager directly
    }

    nonisolated public func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async {
        // Update message queue directly (no event listener Task)
        await messageQueue.updateTranscript(id: itemId, transcript: transcript)
    }

    nonisolated public func realtimeClient(_ client: RealtimeClient, didStartAssistantResponse itemId: String) async {
        // Create message slot directly (no event listener Task)
        await messageQueue.enqueue(
            id: itemId,
            role: .assistant,
            text: nil,
            audioData: nil,
            transcriptStatus: .inProgress
        )
    }

    nonisolated public func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async {
        // Update message queue directly (no event listener Task)
        await messageQueue.updateTranscript(id: itemId, transcript: text)
    }

    nonisolated public func realtimeClientDidFinishAssistantResponse(_ client: RealtimeClient) async {
        // Response completion is handled in didReceiveAssistantResponse
    }

    nonisolated public func realtimeClient(_ client: RealtimeClient, didCommitAudioBuffer itemId: String) async {
        // Create user message slot directly (no event listener Task)
        await messageQueue.enqueue(
            id: itemId,
            role: .user,
            text: nil,
            audioData: nil,
            transcriptStatus: .inProgress
        )
    }

    // MARK: - TurnManagerDelegate Implementation

    nonisolated public func turnManagerDidRequestInterruption(_ manager: TurnManager) async {
        // Interrupt playback directly (no event-based coordination)
        await realtimeClient?.interruptPlayback()
    }

    nonisolated public func turnManagerDidEndUserTurn(_ manager: TurnManager) async {
        // Handle turn end if needed
    }

    // MARK: - Sending Messages

    /// Sends a text message and returns the response (in text mode)
    /// - Parameter text: The message text
    /// - Returns: The assistant's response message (in text mode only)
    /// - Throws: EchoError if sending fails
    public func send(_ text: String) async throws -> Message? {
        switch mode {
        case .audio:
            guard let client = realtimeClient else {
                throw EchoError.clientNotInitialized("Realtime client not initialized")
            }

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
            
            if case .manual = configuration.turnDetection {
                try await client.send(.responseCreate(response: nil))
            }
            
            _ = await messageQueue.enqueue(
                role: .user,
                text: text,
                audioData: nil,
                transcriptStatus: .completed
            )
            
            return nil

        case .text:
            guard let client = responsesClient else {
                throw EchoError.clientNotInitialized("Responses client not initialized")
            }

            _ = await messageQueue.enqueue(
                role: .user,
                text: text,
                audioData: nil,
                transcriptStatus: .notApplicable
            )

            let history = await messageQueue.getOrderedMessages()
            let responsesModel = configuration.responsesModel

            var allResponsesTools: [ResponsesTool] = []
            allResponsesTools.append(contentsOf: tools.map { $0.toResponsesTool() })
            allResponsesTools.append(contentsOf: mcpServers.map { $0.toResponsesTool() })

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
                                    assistantText += delta
                                    
                                case .responseDone(let response):
                                    if let firstText = response.firstText, !firstText.isEmpty {
                                        assistantText = firstText
                                    }
                                    
                                case .responseFailed(let error):
                                    await eventEmitter.emit(.error(error: EchoError.invalidResponse(error)))
                                    
                                case .raw(let type, let data):
                                    if type == "response.output_text.done" {
                                        if let text = data["text"]?.value as? String {
                                            assistantText = text
                                        }
                                    } else if type == "response.output_item.done" {
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
                                        await eventEmitter.emit(.error(error: EchoError.invalidResponse(
                                            "Response was incomplete - the model returned only reasoning without a text response."
                                        )))
                                    }
                                    
                                default:
                                    break
                                }
                            }
                            
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
    public func sendMessage(
        _ text: String,
        responseFormat: ResponseFormat? = nil
    ) async throws -> Message? {
        switch mode {
        case .audio:
            if responseFormat != nil {
                print("[Conversation] Warning: responseFormat is ignored in audio mode")
            }
            _ = try await send(text)
            return nil
            
        case .text:
            guard let client = responsesClient else {
                throw EchoError.clientNotInitialized("Responses client not initialized")
            }
            
            _ = await messageQueue.enqueue(
                role: .user,
                text: text,
                audioData: nil,
                transcriptStatus: .notApplicable
            )
            
            let history = await messageQueue.getOrderedMessages()
            
            var allResponsesTools: [ResponsesTool] = []
            allResponsesTools.append(contentsOf: tools.map { $0.toResponsesTool() })
            allResponsesTools.append(contentsOf: mcpServers.map { $0.toResponsesTool() })
            
            if let format = responseFormat {
                let response = try await client.createResponseWithFormat(
                    model: configuration.responsesModel,
                    input: history,
                    instructions: systemMessage,
                    tools: allResponsesTools,
                    temperature: configuration.temperature,
                    maxOutputTokens: configuration.maxTokens,
                    responseFormat: format
                )
                
                var responseText: String? = response.firstText
                
                if responseText == nil && !response.output.isEmpty {
                    for outputItem in response.output {
                        if case .message(let message) = outputItem {
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
                
                if let firstItem = responseText {
                    let messageId = await messageQueue.enqueue(
                        role: .assistant,
                        text: firstItem,
                        audioData: nil,
                        transcriptStatus: .notApplicable
                    )
                    
                    return await messageQueue.getMessage(byId: messageId)
                }
                return nil
            } else {
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
                                        assistantText += delta
                                        
                                    case .responseDone(let response):
                                        if let firstText = response.firstText, !firstText.isEmpty {
                                            assistantText = firstText
                                        }
                                        
                                    case .responseFailed(let error):
                                        await eventEmitter.emit(.error(error: EchoError.invalidResponse(error)))
                                        
                                    case .raw(let type, let data):
                                        if type == "response.output_text.done" {
                                            if let text = data["text"]?.value as? String {
                                                assistantText = text
                                            }
                                        } else if type == "response.output_item.done" {
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
                                            await eventEmitter.emit(.error(error: EchoError.invalidResponse(
                                                "Response was incomplete - the model returned only reasoning without a text response."
                                            )))
                                        }
                                        
                                    default:
                                        break
                                    }
                                }
                                
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

    // MARK: - Mode Switching

    /// Switches to a different mode
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
        await realtimeClient?.disconnect()
        realtimeClient = nil
        turnManager = nil

        try await initializeTextMode()
    }

    private func transitionTextToAudio() async throws {
        let messages = await messageQueue.getOrderedMessages()

        try await initializeAudioMode()

        responsesClient = nil

        guard let client = realtimeClient else {
            throw EchoError.clientNotInitialized("Realtime client not initialized after initialization")
        }
        
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

    /// Manually ends the user's turn (for manual turn mode)
    public func endUserTurn() async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot end turn in text mode")
        }

        guard case .manual = configuration.turnDetection else {
            return
        }

        await turnManager?.endUserTurn()

        try await realtimeClient?.send(.inputAudioBufferCommit)
        try await realtimeClient?.send(.responseCreate(response: nil))
    }

    /// Interrupts the assistant (stops current response)
    public func interruptAssistant() async throws {
        guard mode == .audio else {
            throw EchoError.invalidMode("Cannot interrupt in text mode")
        }

        await turnManager?.interruptAssistant()

        try await realtimeClient?.send(.responseCancel)
    }

    /// Updates VAD (Voice Activity Detection) settings at runtime
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

        let updatedVAD = VADConfiguration(
            type: currentVAD.type,
            threshold: threshold ?? currentVAD.threshold,
            silenceDurationMs: silenceDuration.map { Int($0.components.seconds * 1000) } ?? currentVAD.silenceDurationMs,
            prefixPaddingMs: prefixPadding.map { Int($0.components.seconds * 1000) } ?? currentVAD.prefixPaddingMs,
            enableInterruption: currentVAD.enableInterruption
        )

        let turnDetectionDict = updatedVAD.toRealtimeFormat()
        let sessionUpdate: [String: Any] = [
            "turn_detection": turnDetectionDict
        ]

        let sessionJSON = try SendableJSON.from(dictionary: sessionUpdate)
        try await client.send(.sessionUpdate(session: sessionJSON))
    }

    // MARK: - Send With Response (Convenience Method)
    
    /// Sends a text message and waits for the complete response
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
}
