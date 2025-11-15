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
