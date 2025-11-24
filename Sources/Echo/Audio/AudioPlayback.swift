// AudioPlayback.swift
// Echo - Audio
// Audio playback using AVFoundation

import Foundation
import AVFoundation

#if os(iOS)
import UIKit
#endif

/// Plays audio received from the Realtime API
public actor AudioPlayback: AudioPlaybackProtocol {
    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let format: AudioFormat
    private let processor: AudioProcessor
    private var isPlaying = false
    private var audioQueue: [Data] = []

    /// Whether playback is currently active
    public var isActive: Bool {
        return isPlaying && (playerNode?.isPlaying ?? false)
    }
    
    /// List of available audio output devices
    public var availableAudioOutputDevices: [AudioOutputDeviceType] {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        var devices: [AudioOutputDeviceType] = []
        
        // Built-in devices are always available
        devices.append(.builtInSpeaker)
        devices.append(.builtInReceiver)
        
        // Check for connected Bluetooth devices
        let availableInputs = audioSession.availableInputs ?? []
        let currentRoute = audioSession.currentRoute
        
        // Get all unique Bluetooth devices from available inputs and current route
        var bluetoothDevices: Set<String> = []
        
        // Check available inputs for Bluetooth devices
        for input in availableInputs {
            if input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP || input.portType == .bluetoothLE {
                let name = input.portName
                if !name.isEmpty {
                    bluetoothDevices.insert(name)
                }
            }
        }
        
        // Check current route outputs for Bluetooth devices
        for output in currentRoute.outputs {
            if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP || output.portType == .bluetoothLE {
                let name = output.portName
                if !name.isEmpty {
                    bluetoothDevices.insert(name)
                }
            }
        }
        
        // Add Bluetooth devices to list
        for name in bluetoothDevices {
            devices.append(.bluetooth(name: name))
        }
        
        // Check for wired headphones
        for output in currentRoute.outputs {
            if output.portType == .headphones {
                let name = output.portName
                devices.append(.wiredHeadphones(name: name.isEmpty ? nil : name))
                break
            }
        }
        
        return devices
        #else
        return [.builtInSpeaker, .builtInReceiver]
        #endif
    }
    
    /// Current active audio output device
    public var currentAudioOutput: AudioOutputDeviceType {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        
        guard let output = currentRoute.outputs.first else {
            return .builtInSpeaker
        }
        
        return AudioOutputDeviceType.from(portType: output.portType, portName: output.portName)
        #else
        return .builtInSpeaker
        #endif
    }

    // MARK: - Initialization

    /// Creates an audio playback instance
    /// - Parameter format: The audio format of incoming data (default: .pcm16)
    public init(format: AudioFormat = .pcm16) {
        self.format = format
        self.processor = AudioProcessor(targetFormat: format)
    }

    // MARK: - Playback Control

    /// Starts the audio playback system
    /// - Throws: RealtimeError if playback fails to start
    public func start() async throws {
        guard !isPlaying else { return }

        do {
            // Configure audio session
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            // Use playAndRecord category to support both input and output
            // .voiceChat mode enables acoustic echo cancellation (AEC)
            // Remove .defaultToSpeaker to use earpiece which has better echo cancellation
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP, .mixWithOthers]
            )
            try audioSession.setActive(true, options: [])
            #endif

            // Create audio engine and player node
            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()

            engine.attach(playerNode)

            guard let playbackFormat = format.makeAVAudioFormat() else {
                throw RealtimeError.unsupportedAudioFormat(format.rawValue)
            }

            // Connect player to output
            engine.connect(
                playerNode,
                to: engine.mainMixerNode,
                format: playbackFormat
            )

            // Start the engine
            try engine.start()

            // Start the player
            playerNode.play()

            self.audioEngine = engine
            self.playerNode = playerNode
            self.isPlaying = true

        } catch {
            throw RealtimeError.audioPlaybackFailed(error)
        }
    }

    /// Stops audio playback
    public func stop() {
        guard isPlaying else { return }

        playerNode?.stop()
        audioEngine?.stop()

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        audioEngine = nil
        playerNode = nil
        isPlaying = false
        audioQueue.removeAll()
    }

    /// Pauses audio playback
    public func pause() {
        playerNode?.pause()
    }

    /// Resumes audio playback
    public func resume() {
        playerNode?.play()
    }

    /// Sets the audio output device
    /// - Parameter device: The audio output device to use
    /// - Throws: RealtimeError if audio playback is not active
    public func setAudioOutput(device: AudioOutputDeviceType) async throws {
        guard isPlaying else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "AudioPlayback", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "Audio playback is not active"
                ])
            )
        }
        
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .mixWithOthers]
        var portOverride: AVAudioSession.PortOverride = .none
        
        switch device {
        case .builtInSpeaker:
            // Force speaker output
            options.insert(.defaultToSpeaker)
            portOverride = .speaker
            
        case .builtInReceiver:
            // Force earpiece (remove speaker override)
            portOverride = .none
            
        case .bluetooth, .wiredHeadphones, .systemDefault:
            // Allow system to route to Bluetooth/wired/earpiece
            // Remove speaker override to allow default routing
            portOverride = .none
        }
        
        // Reconfigure the category with the new options
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: options
        )
        
        // Apply port override
        try audioSession.overrideOutputAudioPort(portOverride)
        #endif
    }

    // MARK: - Audio Enqueueing

    /// Enqueues base64-encoded audio data for playback
    /// - Parameter base64Audio: Base64-encoded audio data
    /// - Throws: AudioProcessorError if decoding fails
    public func enqueue(base64Audio: String) async throws {
        // Decode base64
        let audioData = try await processor.fromBase64(base64Audio)

        // Enqueue the data
        try await enqueue(audioData)
    }

    /// Enqueues raw audio data for playback
    /// - Parameter audioData: Raw audio data in the configured format
    /// - Throws: RealtimeError if enqueueing fails
    public func enqueue(_ audioData: Data) async throws {
        guard let playerNode = playerNode else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "AudioPlayback", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Player not started"
                ])
            )
        }

        guard let playbackFormat = format.makeAVAudioFormat() else {
            throw RealtimeError.unsupportedAudioFormat(format.rawValue)
        }

        // Calculate frame count
        let frameCount = audioData.count / format.bytesPerSample

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw RealtimeError.audioPlaybackFailed(
                NSError(domain: "AudioPlayback", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create audio buffer"
                ])
            )
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy data into buffer
        audioData.withUnsafeBytes { bytes in
            guard let src = bytes.baseAddress else { return }
            guard let dst = buffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, audioData.count)
        }

        // Schedule buffer for playback
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
        }
    }

    /// Clears all queued audio
    public func clearQueue() {
        playerNode?.stop()
        audioQueue.removeAll()
        playerNode?.play()
    }

    /// Immediately stops playback and clears all queued/scheduled audio
    public func interrupt() {
        guard let playerNode = playerNode else { return }

        // Stop playback
        playerNode.stop()

        // CRITICAL: Reset the player node to clear all scheduled buffers
        // Without this, already-scheduled audio will continue playing
        playerNode.reset()

        // Clear our queue (for good measure, though not currently used)
        audioQueue.removeAll()

        // Restart player if engine is still running
        if audioEngine?.isRunning == true {
            playerNode.play()
        }
    }
}
