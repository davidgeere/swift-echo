import Foundation

/// Represents the conversation mode for Echo.
///
/// Echo supports two fundamental modes:
/// - Audio mode: Real-time speech-to-speech conversation using OpenAI's Realtime API
/// - Text mode: Traditional text-based conversation using OpenAI's Responses API
///
/// Conversations can seamlessly switch between modes while preserving full context.
/// Audio interactions are automatically transcribed, ensuring mode-agnostic conversation history.
public enum EchoMode: String, Codable, Sendable, CaseIterable {
    /// Real-time audio conversation mode using WebSocket-based Realtime API.
    /// Supports speech-to-speech interaction with automatic transcription.
    case audio

    /// Text-based conversation mode using REST/SSE-based Responses API.
    /// Traditional message-based interaction.
    case text

    /// User-friendly description of the mode.
    public var description: String {
        switch self {
        case .audio:
            return "Audio Mode"
        case .text:
            return "Text Mode"
        }
    }

    /// Whether this mode supports real-time audio streaming.
    public var supportsAudio: Bool {
        switch self {
        case .audio:
            return true
        case .text:
            return false
        }
    }

    /// Whether this mode requires WebSocket connection.
    public var requiresWebSocket: Bool {
        switch self {
        case .audio:
            return true
        case .text:
            return false
        }
    }
}
