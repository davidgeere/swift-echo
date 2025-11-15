// RealtimeSession.swift
// Echo - Realtime API
// Session configuration and state for Realtime API connections

import Foundation

/// Configuration and state for a Realtime API session
public struct RealtimeSession: Sendable {
    // MARK: - Properties

    /// Unique session ID (assigned by server)
    public let id: String?

    /// Model to use for the session
    public let model: String

    /// Voice to use for text-to-speech
    public let voice: VoiceType

    /// Audio input format
    public let inputAudioFormat: AudioFormat

    /// Audio output format
    public let outputAudioFormat: AudioFormat

    /// Whether to transcribe user audio
    public let inputAudioTranscription: InputAudioTranscription?

    /// Turn detection configuration
    public let turnDetection: TurnDetection?

    /// System instructions for the model
    public let instructions: String?

    /// Tools available for function calling
    public let tools: [SendableJSON]?

    /// Tool choice configuration
    public let toolChoice: String?

    /// Sampling temperature (0.0-2.0)
    public let temperature: Double?

    /// Maximum output tokens per response
    public let maxResponseOutputTokens: Int?

    // MARK: - Initialization

    /// Creates a session configuration
    /// - Parameters:
    ///   - id: Session ID (assigned by server, nil for new sessions)
    ///   - model: Realtime model to use
    ///   - voice: Voice for text-to-speech
    ///   - inputAudioFormat: Input audio format
    ///   - outputAudioFormat: Output audio format
    ///   - inputAudioTranscription: Transcription config
    ///   - turnDetection: Turn detection config
    ///   - instructions: System instructions
    ///   - tools: Available tools
    ///   - toolChoice: Tool choice strategy
    ///   - temperature: Sampling temperature
    ///   - maxResponseOutputTokens: Max output tokens
    public init(
        id: String? = nil,
        model: RealtimeModel,
        voice: VoiceType = .alloy,
        inputAudioFormat: AudioFormat = .pcm16,
        outputAudioFormat: AudioFormat = .pcm16,
        inputAudioTranscription: InputAudioTranscription? = InputAudioTranscription(),
        turnDetection: TurnDetection? = .default,
        instructions: String? = nil,
        tools: [SendableJSON]? = nil,
        toolChoice: String? = nil,
        temperature: Double? = 0.8,
        maxResponseOutputTokens: Int? = nil
    ) {
        self.id = id
        self.model = model.rawValue
        self.voice = voice
        self.inputAudioFormat = inputAudioFormat
        self.outputAudioFormat = outputAudioFormat
        self.inputAudioTranscription = inputAudioTranscription
        self.turnDetection = turnDetection
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
        self.temperature = temperature
        self.maxResponseOutputTokens = maxResponseOutputTokens
    }

    // MARK: - Conversion

    /// Converts to the format expected by the Realtime API
    public func toRealtimeFormat() -> [String: Any] {
        var config: [String: Any] = [
            "modalities": ["text", "audio"],
            "voice": voice.rawValue,
            "input_audio_format": inputAudioFormat.rawValue,
            "output_audio_format": outputAudioFormat.rawValue
        ]

        if let transcription = inputAudioTranscription {
            config["input_audio_transcription"] = transcription.toRealtimeFormat()
        }

        if let turnDetection = turnDetection?.toRealtimeFormat() {
            config["turn_detection"] = turnDetection
        }

        if let instructions = instructions {
            config["instructions"] = instructions
        }

        if let tools = tools {
            let toolDicts = try? tools.map { try $0.toDictionary() }
            config["tools"] = toolDicts
        }

        if let toolChoice = toolChoice {
            config["tool_choice"] = toolChoice
        }

        if let temperature = temperature {
            // CRITICAL: Store as string formatted to 1 decimal place
            // Double precision errors make 0.8 become 0.80000000000000004
            // We'll convert this to a proper number in RequestBuilder
            let formatted = String(format: "%.1f", temperature)
            config["__temperature_string"] = formatted

            print("[RealtimeSession] Temperature value (formatted): \(formatted)")
        }

        if let maxTokens = maxResponseOutputTokens {
            config["max_response_output_tokens"] = maxTokens
        }

        return config
    }
}

// Note: InputAudioTranscription and SessionState are now in their own files
// for better organization per the architecture document's one-type-per-file rule.
