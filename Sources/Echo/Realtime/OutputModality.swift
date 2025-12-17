// OutputModality.swift
// Echo - Realtime API
// Output modality configuration for Realtime API responses

import Foundation

/// Output modality configuration for Realtime API responses.
///
/// According to OpenAI's Realtime API documentation:
/// - `["audio"]` (default): Model responds with audio plus a transcript
/// - `["text"]`: Model responds with text only
///
/// **It is not possible to request both text and audio at the same time.**
///
/// Use `.audio` for voice conversations and `.text` when you want
/// text-only responses (e.g., when the user is typing instead of speaking).
public enum OutputModality: String, Sendable, Codable, CaseIterable {
    /// Audio mode - model responds with audio plus a transcript.
    /// This is the default for voice conversations.
    case audio
    
    /// Text mode - model responds with text only.
    /// Use this when the user is typing instead of speaking.
    case text
    
    // MARK: - Properties
    
    /// Returns the array format expected by the Realtime API.
    ///
    /// - Note: OpenAI expects an array like `["audio"]` or `["text"]`
    public var apiValue: [String] {
        switch self {
        case .audio:
            return ["audio"]
        case .text:
            return ["text"]
        }
    }
    
    /// User-friendly description of the modality.
    public var description: String {
        switch self {
        case .audio:
            return "Audio (voice + transcript)"
        case .text:
            return "Text only"
        }
    }
    
    /// Whether this modality produces audio output.
    public var producesAudio: Bool {
        switch self {
        case .audio:
            return true
        case .text:
            return false
        }
    }
    
    /// Whether this modality produces text output.
    /// Note: Audio mode also produces a transcript, so both modalities produce text.
    public var producesText: Bool {
        return true // Both modes produce text (audio mode includes transcript)
    }
}

