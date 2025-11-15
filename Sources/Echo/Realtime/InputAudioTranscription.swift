// InputAudioTranscription.swift
// Echo - Realtime API
// Configuration for input audio transcription

import Foundation

/// Configuration for input audio transcription
public struct InputAudioTranscription: Sendable {
    /// Transcription model to use
    public let model: TranscriptionModel

    /// Creates transcription configuration
    /// - Parameter model: Transcription model (default: .whisper1)
    public init(model: TranscriptionModel = .whisper1) {
        self.model = model
    }

    /// Converts to Realtime API format
    public func toRealtimeFormat() -> [String: Any] {
        return [
            "model": model.rawValue
        ]
    }
}
