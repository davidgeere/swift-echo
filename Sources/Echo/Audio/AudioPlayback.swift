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

        #if DEBUG
        print("[AudioPlayback] 🎵 Starting audio playback...")
        #endif

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
            
            #if DEBUG
            let currentRoute = audioSession.currentRoute
            print("[AudioPlayback] 🎵 Audio session activated")
            print("[AudioPlayback] 🎵 Current output route: \(currentRoute.outputs.map { "\($0.portType.rawValue) - \($0.portName)" }.joined(separator: ", "))")
            #endif
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

            #if DEBUG
            print("[AudioPlayback] ✅ Audio playback started successfully")
            print("[AudioPlayback] 🎵 Engine running: \(engine.isRunning)")
            print("[AudioPlayback] 🎵 Player playing: \(playerNode.isPlaying)")
            #endif

        } catch {
            #if DEBUG
            print("[AudioPlayback] ❌ Failed to start audio playback: \(error)")
            #endif
            throw RealtimeError.audioPlaybackFailed(error)
        }
    }

    /// Stops audio playback
    public func stop() {
        guard isPlaying else { return }

        #if DEBUG
        print("[AudioPlayback] 🛑 Stopping audio playback...")
        print("[AudioPlayback] 🎵 Engine running before stop: \(audioEngine?.isRunning ?? false)")
        print("[AudioPlayback] 🎵 Player playing before stop: \(playerNode?.isPlaying ?? false)")
        #endif

        playerNode?.stop()
        audioEngine?.stop()

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        audioEngine = nil
        playerNode = nil
        isPlaying = false
        audioQueue.removeAll()

        #if DEBUG
        print("[AudioPlayback] ✅ Audio playback stopped")
        #endif
    }

    /// Pauses audio playback
    public func pause() {
        #if DEBUG
        print("[AudioPlayback] ⏸️ Pausing audio playback")
        #endif
        playerNode?.pause()
    }

    /// Resumes audio playback
    public func resume() {
        #if DEBUG
        print("[AudioPlayback] ▶️ Resuming audio playback")
        print("[AudioPlayback] 🎵 Engine running: \(audioEngine?.isRunning ?? false)")
        print("[AudioPlayback] 🎵 Player playing: \(playerNode?.isPlaying ?? false)")
        #endif
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
        
        #if DEBUG
        print("[AudioPlayback] 🔊 Setting audio output device to: \(device.description)")
        print("[AudioPlayback] 🎵 Engine running before switch: \(audioEngine?.isRunning ?? false)")
        print("[AudioPlayback] 🎵 Player playing before switch: \(playerNode?.isPlaying ?? false)")
        #endif
        
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
        
        // CRITICAL FIX: Remember engine state before session changes
        let wasEngineRunning = audioEngine?.isRunning ?? false
        let wasPlayerPlaying = playerNode?.isPlaying ?? false
        
        // Try to reconfigure without deactivating first (preserves engines)
        // Clear any existing override
        do {
            try audioSession.overrideOutputAudioPort(.none)
        } catch {
            // If clearing fails, we need to deactivate
            #if DEBUG
            print("[AudioPlayback] 🔊 Could not clear override, deactivating session...")
            #endif
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        }
        
        // Reconfigure the category with the new options
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: options
        )
        
        // Reactivate the session if it was deactivated
        if !audioSession.isOtherAudioPlaying {
            try audioSession.setActive(true)
        }
        
        // Apply port override
        try audioSession.overrideOutputAudioPort(portOverride)
        
        // Restart engines if they were running before
        if wasEngineRunning {
            if let engine = audioEngine, !engine.isRunning {
                #if DEBUG
                print("[AudioPlayback] ▶️ Restarting engine after session change...")
                #endif
                try engine.start()
            }
            if let playerNode = playerNode, wasPlayerPlaying && !playerNode.isPlaying {
                playerNode.play()
            }
        }
        
        #if DEBUG
        let currentRoute = audioSession.currentRoute
        print("[AudioPlayback] 🔊 Audio session reconfigured")
        print("[AudioPlayback] 🔊 New output route: \(currentRoute.outputs.map { "\($0.portType.rawValue) - \($0.portName)" }.joined(separator: ", "))")
        print("[AudioPlayback] 🎵 Engine running after switch: \(audioEngine?.isRunning ?? false)")
        print("[AudioPlayback] 🎵 Player playing after switch: \(playerNode?.isPlaying ?? false)")
        #endif
        
        // Check if engines stopped and restart if needed
        if let engine = audioEngine, !engine.isRunning {
            #if DEBUG
            print("[AudioPlayback] ⚠️ Engine stopped after session change, restarting...")
            #endif
            do {
                // Stop engine first if it's in a bad state
                engine.stop()
                
                // Small delay to let engine fully stop
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                
                // Restart the engine
                try engine.start()
                
                // Small delay to let engine fully start
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                
                if let playerNode = playerNode, !playerNode.isPlaying {
                    playerNode.play()
                }
                
                #if DEBUG
                let isRunning = engine.isRunning
                let isPlaying = playerNode?.isPlaying ?? false
                print("[AudioPlayback] ✅ Engine restart attempted - running: \(isRunning), player playing: \(isPlaying)")
                
                if !isRunning {
                    print("[AudioPlayback] ⚠️ WARNING: Engine restart returned but engine is not running!")
                }
                #endif
            } catch {
                #if DEBUG
                print("[AudioPlayback] ❌ Failed to restart engine: \(error)")
                #endif
                // Re-throw the error so caller knows restart failed
                throw RealtimeError.audioPlaybackFailed(error)
            }
        }
        
        // CRITICAL FIX: Give iOS a moment to apply the route change
        // This ensures currentAudioOutput reflects the new route
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        #endif
    }

    // MARK: - Audio Enqueueing

    /// Enqueues base64-encoded audio data for playback
    /// - Parameter base64Audio: Base64-encoded audio data
    /// - Throws: AudioProcessorError if decoding fails
    public func enqueue(base64Audio: String) async throws {
        #if DEBUG
        let audioSize = base64Audio.count
        print("[AudioPlayback] 📥 Enqueueing audio chunk (base64 size: \(audioSize) bytes)")
        #endif
        
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
                #if DEBUG
                print("[AudioPlayback] ✅ Audio buffer scheduled and played")
                #endif
                continuation.resume()
            }
        }
    }

    /// Clears all queued audio
    public func clearQueue() {
        #if DEBUG
        print("[AudioPlayback] 🧹 Clearing audio queue")
        #endif
        playerNode?.stop()
        audioQueue.removeAll()
        playerNode?.play()
    }

    /// Immediately stops playback and clears all queued/scheduled audio
    public func interrupt() {
        guard let playerNode = playerNode else { return }

        #if DEBUG
        print("[AudioPlayback] ⚡ Interrupting playback")
        #endif

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
            #if DEBUG
            print("[AudioPlayback] ✅ Player restarted after interrupt")
            #endif
        } else {
            #if DEBUG
            print("[AudioPlayback] ⚠️ Engine not running, cannot restart player")
            #endif
        }
    }
}
