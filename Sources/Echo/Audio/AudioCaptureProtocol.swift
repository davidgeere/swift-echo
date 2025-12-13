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

    // MARK: - Echo Protection Gating

    /// Enables audio gating for echo protection
    ///
    /// When gating is enabled, only audio chunks with RMS level above the threshold
    /// will be forwarded to the callback. This helps filter out echo (quieter) while
    /// allowing genuine user speech (louder) to pass through.
    ///
    /// - Parameter threshold: RMS level threshold (0.0-1.0). Audio below this level is filtered.
    func enableGating(threshold: Float) async

    /// Disables audio gating
    ///
    /// All captured audio will be forwarded to the callback regardless of level.
    func disableGating() async

    /// Whether audio gating is currently enabled
    var isGatingEnabled: Bool { get }

    // MARK: - Echo Cancellation

    /// Sets the echo canceller for correlation-based filtering
    ///
    /// When set, the capture will use the echo canceller to detect and suppress
    /// audio that correlates with recently played output audio.
    ///
    /// - Parameter canceller: The echo canceller to use, or nil to disable
    func setEchoCanceller(_ canceller: EchoCanceller?) async
}
