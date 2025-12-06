// AudioPlayback.swift
// Echo - Audio
// Audio playback using AVFoundation

import Foundation
import AVFoundation
import os

#if os(iOS)
import UIKit
#endif

/// Plays audio received from the Realtime API
public actor AudioPlayback: AudioPlaybackProtocol {
    // MARK: - Properties

    /// The underlying AVAudioEngine (for external audio monitoring)
    public private(set) var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let format: AudioFormat
    private let processor: AudioProcessor
    private var isPlaying = false
    private var audioQueue: [Data] = []

    /// Frequency analyzer for FFT-based level analysis
    private let analyzer = FrequencyAnalyzer()
    
    /// Current smoothed levels (thread-safe via lock)
    private let currentLevels = OSAllocatedUnfairLock(initialState: AudioLevels.zero)
    
    /// Smoothing factor for level transitions (0.0-1.0, higher = faster response)
    private let smoothingFactor: Float = 0.3
    
    /// Audio level stream for output visualizations
    public let audioLevelStream: AsyncStream<AudioLevels>
    private let audioLevelContinuation: AsyncStream<AudioLevels>.Continuation

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
        
        var levelCont: AsyncStream<AudioLevels>.Continuation?
        self.audioLevelStream = AsyncStream { continuation in
            levelCont = continuation
        }
        guard let unwrappedLevelCont = levelCont else {
            preconditionFailure("Failed to initialize audio level stream continuation")
        }
        self.audioLevelContinuation = unwrappedLevelCont
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
            
            // Install tap on main mixer for output level monitoring
            let mainMixer = engine.mainMixerNode
            let mixerFormat = mainMixer.outputFormat(forBus: 0)
            let sampleRate = Float(mixerFormat.sampleRate)
            
            mainMixer.installTap(onBus: 0, bufferSize: 2048, format: mixerFormat) { [weak self] buffer, _ in
                guard let self else { return }
                
                // Extract samples synchronously on audio thread
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                
                // Process on audio thread (analyzer is thread-safe)
                let newLevels = self.analyzer.analyze(samples: samples, sampleRate: sampleRate)
                
                // Apply smoothing and yield
                let smoothedLevels = self.currentLevels.withLock { current in
                    let smoothed = AudioLevels(
                        level: current.level + (newLevels.level - current.level) * self.smoothingFactor,
                        low: current.low + (newLevels.low - current.low) * self.smoothingFactor,
                        mid: current.mid + (newLevels.mid - current.mid) * self.smoothingFactor,
                        high: current.high + (newLevels.high - current.high) * self.smoothingFactor
                    )
                    current = smoothed
                    return smoothed
                }
                
                // Yield to stream
                self.audioLevelContinuation.yield(smoothedLevels)
            }

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

        // Remove tap before stopping
        audioEngine?.mainMixerNode.removeTap(onBus: 0)
        
        playerNode?.stop()
        audioEngine?.stop()

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        audioEngine = nil
        playerNode = nil
        isPlaying = false
        audioQueue.removeAll()
        
        // Reset levels
        currentLevels.withLock { $0 = .zero }
        audioLevelContinuation.yield(.zero)
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
        
        // CRITICAL FIX: Stop engines BEFORE route change to prevent route caching
        let wasEngineRunning = audioEngine?.isRunning ?? false
        let wasPlayerPlaying = playerNode?.isPlaying ?? false
        
        // Step 1: Stop engine and player FIRST to prevent route caching
        if wasEngineRunning {
            audioEngine?.stop()
            playerNode?.stop()
            // Wait for engine to fully stop
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        
        // Step 2: Clear any existing override
        do {
            try audioSession.overrideOutputAudioPort(.none)
        } catch {
            // If clearing fails, we need to deactivate
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        }
        
        // Step 3: Reconfigure the category with the new options
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: options
        )
        
        // Step 4: Reactivate the session if it was deactivated
        if !audioSession.isOtherAudioPlaying {
            try audioSession.setActive(true)
        }
        
        // Step 5: Apply port override AFTER session is active
        try audioSession.overrideOutputAudioPort(portOverride)
        
        // Step 6: Wait for route change to take effect BEFORE restarting engine
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms - longer delay for route to stabilize
        
        // Step 7: Verify route actually changed (especially for speaker)
        let verifyRoute = audioSession.currentRoute
        let actualOutput = verifyRoute.outputs.first?.portType ?? .builtInReceiver
        if device == .builtInSpeaker && actualOutput != .builtInSpeaker {
            // Try override again
            try audioSession.overrideOutputAudioPort(.speaker)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        // Step 8: NOW restart engines if they were running before
        if wasEngineRunning {
            if let engine = audioEngine, !engine.isRunning {
                do {
                    try engine.start()
                    
                    // Small delay to let engine fully start
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    
                    if let playerNode = playerNode, wasPlayerPlaying && !playerNode.isPlaying {
                        playerNode.play()
                    }
                } catch {
                    throw RealtimeError.audioPlaybackFailed(error)
                }
            }
        }
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

        // CRITICAL FIX: Restart engine if it stopped (can happen after audio output changes)
        if let engine = audioEngine, !engine.isRunning {
            do {
                try engine.start()
            } catch {
                // Don't throw - just log, we'll try to continue
            }
        }

        // Restart player if engine is running
        if audioEngine?.isRunning == true {
            playerNode.play()
        }
    }
    
    deinit {
        audioLevelContinuation.finish()
    }
}
