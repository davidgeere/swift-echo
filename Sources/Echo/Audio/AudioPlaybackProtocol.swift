// AudioPlaybackProtocol.swift
// Echo - Audio
// Protocol for audio playback to enable testing without hardware

import Foundation

/// Protocol for audio playback implementations
/// Allows injecting mock audio playback for testing without speakers
public protocol AudioPlaybackProtocol: Actor {
    /// Starts audio playback
    func start() async throws
    
    /// Stops audio playback
    func stop() async
    
    /// Enqueues audio data for playback
    /// - Parameter base64Audio: Base64-encoded audio data
    func enqueue(base64Audio: String) async throws
    
    /// Interrupts current playback (clears queue)
    func interrupt() async
    
    /// Sets the audio output device
    /// - Parameter device: The audio output device to use
    /// - Throws: RealtimeError if audio playback is not active
    func setAudioOutput(device: AudioOutputDeviceType) async throws
    
    /// List of available audio output devices
    var availableAudioOutputDevices: [AudioOutputDeviceType] { get }
    
    /// Current active audio output device
    var currentAudioOutput: AudioOutputDeviceType { get }
}
