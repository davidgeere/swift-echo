// AudioCaptureProtocol.swift
// Echo - Audio
// Protocol for audio capture to enable testing without hardware

import Foundation

/// Protocol for audio capture implementations
/// Allows injecting mock audio capture for testing without microphone hardware
public protocol AudioCaptureProtocol: Actor {
    /// Starts capturing audio
    /// - Parameter onAudioChunk: Callback that receives base64-encoded audio chunks
    func start(onAudioChunk: @escaping @Sendable (String) async -> Void) async throws

    /// Stops capturing audio
    func stop() async

    /// Pauses audio capture
    func pause() async

    /// Resumes audio capture
    func resume() async throws

    /// Stream of audio levels for visualization including frequency bands
    var audioLevelStream: AsyncStream<AudioLevels> { get }
    
    /// Whether audio is currently being captured
    var isActive: Bool { get }
}
