// WebRTCAudioHandler.swift
// Echo - Audio
// Handles WebRTC audio track management

@preconcurrency import AVFoundation
import Foundation

#if canImport(AmazonChimeSDKMedia)
import AmazonChimeSDKMedia
#endif

/// Handles WebRTC audio input and output tracks
///
/// For WebRTC transport, audio flows through RTCPeerConnection media tracks
/// rather than base64-encoded events. This handler manages:
/// - Local audio track (microphone input)
/// - Remote audio track (model output)
/// - Audio session configuration
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
    
    /// The current audio output device
    public private(set) var currentAudioOutput: AudioOutputDeviceType = .systemDefault
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Audio Session Configuration
    
    /// Configures the audio session for WebRTC
    ///
    /// Sets up the AVAudioSession with appropriate category, mode, and options
    /// for real-time voice communication.
    ///
    /// - Throws: Error if audio session configuration fails
    public func configureAudioSession() async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        do {
            // Configure for voice chat with echo cancellation
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .defaultToSpeaker,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .mixWithOthers
                ]
            )
            
            // Set preferred sample rate for WebRTC (24kHz for OpenAI Realtime)
            try session.setPreferredSampleRate(24000)
            
            // Activate the session
            try session.setActive(true)
            
            state = .configured
            print("[WebRTCAudioHandler] ✅ Audio session configured")
            
        } catch {
            state = .error(error)
            throw error
        }
        #else
        // macOS doesn't require explicit audio session configuration
        state = .configured
        #endif
    }
    
    /// Deactivates the audio session
    public func deactivateAudioSession() async {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            state = .idle
            print("[WebRTCAudioHandler] ✅ Audio session deactivated")
        } catch {
            print("[WebRTCAudioHandler] ⚠️ Failed to deactivate audio session: \(error)")
        }
        #else
        state = .idle
        #endif
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
    /// - Parameter device: The target audio output device
    /// - Throws: Error if the device change fails
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        do {
            switch device {
            case .builtInSpeaker:
                try session.overrideOutputAudioPort(.speaker)
                
            case .builtInReceiver:
                try session.overrideOutputAudioPort(.none)
                // Set to voice chat mode which uses receiver
                try session.setCategory(.playAndRecord, mode: .voiceChat)
                
            case .bluetooth, .wiredHeadphones, .systemDefault, .smart:
                try session.overrideOutputAudioPort(.none)
            }
            
            currentAudioOutput = device
            print("[WebRTCAudioHandler] 🔊 Audio output set to: \(device)")
            
        } catch {
            print("[WebRTCAudioHandler] ❌ Failed to set audio output: \(error)")
            throw error
        }
        #else
        currentAudioOutput = device
        #endif
    }
    
    /// Gets available audio output devices
    public var availableAudioOutputDevices: [AudioOutputDeviceType] {
        #if os(iOS)
        var devices: [AudioOutputDeviceType] = [.builtInSpeaker, .builtInReceiver]
        
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute
        
        for output in currentRoute.outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                if !devices.contains(.bluetooth) {
                    devices.append(.bluetooth)
                }
            case .headphones:
                if !devices.contains(.wiredHeadphones) {
                    devices.append(.wiredHeadphones)
                }
            default:
                break
            }
        }
        
        return devices
        #else
        return [.systemDefault]
        #endif
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

