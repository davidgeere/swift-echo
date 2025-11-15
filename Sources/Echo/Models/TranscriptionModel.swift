// TranscriptionModel.swift
// Echo - Models
// Supported transcription models for speech-to-text

import Foundation

/// Supported OpenAI transcription models for speech-to-text
public enum TranscriptionModel: String, CaseIterable, Codable, Sendable {
    /// Whisper-1: OpenAI's automatic speech recognition (ASR) model
    case whisper1 = "whisper-1"
    
    /// Returns a human-readable description of the model
    public var description: String {
        switch self {
        case .whisper1:
            return "OpenAI Whisper automatic speech recognition model"
        }
    }
    
    /// Returns the supported languages count for this model
    public var supportedLanguagesCount: Int {
        switch self {
        case .whisper1:
            return 98  // Whisper supports 98 languages
        }
    }
    
    /// Returns whether this model supports word-level timestamps
    public var supportsTimestamps: Bool {
        switch self {
        case .whisper1:
            return true
        }
    }
    
    /// Validates that the model string is a supported transcription model
    /// - Parameter modelString: The model string to validate
    /// - Returns: The validated TranscriptionModel
    /// - Throws: EchoError if the model is not supported
    public static func validate(_ modelString: String) throws -> TranscriptionModel {
        guard let model = TranscriptionModel(rawValue: modelString) else {
            throw EchoError.unsupportedModel(
                "Model '\(modelString)' is not a supported transcription model. " +
                "Valid model: whisper-1"
            )
        }
        return model
    }
}

// MARK: - Default Model

extension TranscriptionModel {
    /// The default transcription model (whisper-1)
    public static let `default` = TranscriptionModel.whisper1
}
