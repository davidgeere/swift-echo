// WebRTCAudioHandler.swift
// Echo - Audio
// Handles WebRTC audio track management

import Foundation
import WebRTC

/// Handles WebRTC audio input and output tracks
///
/// For WebRTC transport, audio flows through RTCPeerConnection media tracks
/// rather than base64-encoded events. This handler manages:
/// - Local audio track (microphone input)
/// - Remote audio track (model output)
/// - Audio session configuration (delegated to AudioSessionManager)
/// - Mute/unmute functionality
public actor WebRTCAudioHandler {
    // MARK: - Types
    
    /// Audio handler state
    public enum State: Sendable {
        case idle
        case configured
        case active
        case error(Error)
    }
    
    // MARK: - Properties
    
    private var state: State = .idle
    private var isMuted: Bool = false
    
    /// Reference to the shared audio session manager
    private let sessionManager = AudioSessionManager.shared
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Audio Session Configuration
    
    /// Configures the audio session for WebRTC
    ///
    /// Sets up the AVAudioSession with appropriate category, mode, and options
    /// for real-time voice communication. Delegates to AudioSessionManager.
    ///
    /// - Throws: Error if audio session configuration fails
    public func configureAudioSession() async throws {
        do {
            // Delegate to shared manager - WebRTC defaults to speaker
            try await sessionManager.configureForVoiceChat(defaultToSpeaker: true)
            
            // Start observing route changes so we can react to Bluetooth/headphone events
            await sessionManager.startRouteChangeObservation()
            
            state = .configured
            print("[WebRTCAudioHandler] ✅ Audio session configured via AudioSessionManager")
            
        } catch {
            state = .error(error)
            throw error
        }
    }
    
    /// Deactivates the audio session
    public func deactivateAudioSession() async {
        await sessionManager.stopRouteChangeObservation()
        await sessionManager.deactivate()
        state = .idle
        print("[WebRTCAudioHandler] ✅ Audio session deactivated via AudioSessionManager")
    }
    
    // MARK: - Audio Control
    
    /// Sets whether the local audio (microphone) is muted
    ///
    /// - Parameter muted: Whether to mute the microphone
    public func setMuted(_ muted: Bool) {
        isMuted = muted
        // Note: Actual track muting is handled by the WebRTC peer connection
        print("[WebRTCAudioHandler] 🎤 Muted: \(muted)")
    }
    
    /// Whether the local audio is currently muted
    public var isAudioMuted: Bool {
        isMuted
    }
    
    /// Sets the audio output device
    ///
    /// Delegates to AudioSessionManager which handles verification and route changes.
    ///
    /// - Parameter device: The target audio output device
    /// - Throws: Error if the device change fails
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        try await sessionManager.setAudioOutput(device: device)
        print("[WebRTCAudioHandler] 🔊 Audio output set to: \(device)")
    }
    
    /// The current audio output device
    ///
    /// Computed property that queries AudioSessionManager for actual system state.
    /// This ensures the value never drifts from reality.
    public var currentAudioOutput: AudioOutputDeviceType {
        get async {
            await sessionManager.currentAudioOutput
        }
    }
    
    /// Gets available audio output devices
    ///
    /// Delegates to AudioSessionManager for consistent device enumeration.
    public var availableAudioOutputDevices: [AudioOutputDeviceType] {
        get async {
            await sessionManager.availableAudioOutputDevices
        }
    }
    
    // MARK: - State
    
    /// The current state of the audio handler
    public var currentState: State {
        state
    }
    
    /// Whether the audio handler is ready for use
    public var isReady: Bool {
        switch state {
        case .configured, .active:
            return true
        default:
            return false
        }
    }
}
