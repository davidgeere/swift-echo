// AudioStatus.swift
// Echo - Audio Infrastructure
// Represents the audio status of the Echo system

import Foundation

/// Represents the audio status of the Echo system
public enum AudioStatus: Sendable {
    /// System is listening for user input
    case listening

    /// Assistant is speaking
    case speaking

    /// System is processing (thinking)
    case processing

    /// System is idle
    case idle
}
