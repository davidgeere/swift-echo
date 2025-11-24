import Foundation

/// Configuration for Echo conversations.
///
/// Defines all settings for initializing and managing Echo conversations,
/// including mode selection, model choices, audio settings, and behavior options.
public struct EchoConfiguration: Sendable {
    // MARK: - Mode and Models

    /// Default conversation mode (audio or text).
    public let defaultMode: EchoMode

    /// Model to use for Realtime API (audio mode).
    public let realtimeModel: RealtimeModel

    /// Model to use for Responses API (text mode).
    public let responsesModel: ResponsesModel

    // MARK: - Audio Settings

    /// Audio format for Realtime API.
    public let audioFormat: AudioFormat

    /// Voice type for text-to-speech.
    public let voice: VoiceType

    // MARK: - Turn Detection

    /// Turn detection configuration for audio mode.
    public let turnDetection: TurnDetection?

    // MARK: - Model Parameters

    /// Sampling temperature (0.0-2.0).
    /// Higher values make output more random, lower values more deterministic.
    /// Note: Only used for Realtime API (audio mode). GPT-5 models do not support temperature.
    public let temperature: Double

    /// Maximum tokens for response generation.
    public let maxTokens: Int?
    
    /// Reasoning effort level for controlling depth of model reasoning
    /// Set to .none to minimize reasoning output, or .high for complex problems
    public let reasoningEffort: ReasoningEffort

    // MARK: - System Instructions

    /// Default system message/instructions for all conversations.
    /// Can be overridden per-conversation when calling startConversation().
    public let systemMessage: String?

    // MARK: - Transcription

    /// Whether to enable transcription in audio mode.
    /// When enabled, all audio interactions are converted to text.
    public let enableTranscription: Bool

    // MARK: - Logging

    /// Logging level for debugging.
    public let logLevel: LogLevel

    // MARK: - Initialization

    /// Creates a new Echo configuration with the specified settings.
    ///
    /// - Parameters:
    ///   - defaultMode: The initial conversation mode (default: .text)
    ///   - realtimeModel: Model for audio mode (default: .gptRealtime)
    ///   - responsesModel: Model for text mode (default: .gpt5)
    ///   - audioFormat: Audio format (default: .pcm16)
    ///   - voice: Voice type (default: .alloy)
    ///   - turnDetection: Turn detection mode (default: automatic with standard settings)
    ///   - temperature: Sampling temperature (default: 0.8)
    ///   - maxTokens: Maximum response tokens (default: nil for unlimited)
    ///   - reasoningEffort: Reasoning depth control (default: .none to minimize reasoning)
    ///   - systemMessage: Default system instructions for all conversations (default: nil)
    ///   - enableTranscription: Enable audio transcription (default: true)
    ///   - logLevel: Logging verbosity (default: .info)
    public init(
        defaultMode: EchoMode = .text,
        realtimeModel: RealtimeModel = .gptRealtime,
        responsesModel: ResponsesModel = .gpt5,
        audioFormat: AudioFormat = .pcm16,
        voice: VoiceType = .alloy,
        turnDetection: TurnDetection? = .default,
        temperature: Double = 0.8,
        maxTokens: Int? = nil,
        reasoningEffort: ReasoningEffort = .none,
        systemMessage: String? = nil,
        enableTranscription: Bool = true,
        logLevel: LogLevel = .info
    ) {
        self.defaultMode = defaultMode
        self.realtimeModel = realtimeModel
        self.responsesModel = responsesModel
        self.audioFormat = audioFormat
        self.voice = voice
        self.turnDetection = turnDetection
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
        self.systemMessage = systemMessage
        self.enableTranscription = enableTranscription
        self.logLevel = logLevel
    }

    /// Default configuration with sensible defaults.
    public static let `default` = EchoConfiguration()

    // MARK: - Conversions

    /// Converts to RealtimeClientConfiguration
    public func toRealtimeClientConfiguration() -> RealtimeClientConfiguration {
        return RealtimeClientConfiguration(
            model: realtimeModel,
            voice: voice,
            audioFormat: audioFormat,
            turnDetection: turnDetection,
            instructions: systemMessage,
            enableTranscription: enableTranscription,
            startAudioAutomatically: true,
            temperature: temperature,
            maxOutputTokens: maxTokens
        )
    }
}

// MARK: - Supporting Types

// Note: AudioFormat, VoiceType, and TurnDetection are in the Audio/ and Realtime/ directories.
// Note: EchoError, LogLevel, and Duration extensions are in their own files for better organization.
