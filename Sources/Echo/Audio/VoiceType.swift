// VoiceType.swift
// Echo - Audio
// Voice types for text-to-speech

import Foundation

/// Available voice types for text-to-speech in the Realtime API
public enum VoiceType: String, Sendable, CaseIterable, Codable {
    /// Alloy voice - balanced and neutral
    case alloy = "alloy"

    /// Ash voice - warm and conversational
    case ash = "ash"

    /// Ballad voice - expressive and storytelling
    case ballad = "ballad"

    /// Coral voice - friendly and upbeat
    case coral = "coral"

    /// Echo voice - energetic and dynamic
    case echo = "echo"

    /// Sage voice - calm and measured
    case sage = "sage"

    /// Shimmer voice - light and airy
    case shimmer = "shimmer"

    /// Verse voice - clear and articulate
    case verse = "verse"
}
