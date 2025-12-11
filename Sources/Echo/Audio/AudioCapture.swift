// AudioCapture.swift
// Echo - Audio
// Microphone audio capture using AVFoundation

import Foundation
@preconcurrency import AVFoundation
import os

#if os(iOS)
import UIKit
#endif

/// Captures audio from the microphone for the Realtime API
public actor AudioCapture: AudioCaptureProtocol {
    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let format: AudioFormat
    private let processor: AudioProcessor
    private var isCapturing = false

    /// Frequency analyzer for FFT-based level analysis
    private let analyzer = FrequencyAnalyzer()

    /// Current smoothed levels (thread-safe via lock)
    private let currentLevels = OSAllocatedUnfairLock(initialState: AudioLevels.zero)

    /// Smoothing factor for level transitions (0.0-1.0, higher = faster response)
    private let smoothingFactor: Float = 0.3

    /// Audio level stream for visualizations
    public let audioLevelStream: AsyncStream<AudioLevels>
    private let audioLevelContinuation: AsyncStream<AudioLevels>.Continuation

    // MARK: - Gating Properties (Echo Protection)

    /// Whether audio gating is enabled (thread-safe via lock)
    private let gatingState = OSAllocatedUnfairLock(initialState: GatingState(isEnabled: false, threshold: 0.0))

    /// State for audio gating
    private struct GatingState {
        var isEnabled: Bool
        var threshold: Float
    }

    /// Whether audio gating is currently enabled
    public var isGatingEnabled: Bool {
        return gatingState.withLock { $0.isEnabled }
    }

    // MARK: - Initialization

    /// Creates an audio capture instance
    /// - Parameter format: The target audio format (default: .pcm16)
    public init(format: AudioFormat = .pcm16) {
        self.format = format
        self.processor = AudioProcessor(targetFormat: format)

        var levelCont: AsyncStream<AudioLevels>.Continuation?
        self.audioLevelStream = AsyncStream { continuation in
            levelCont = continuation
        }
        self.audioLevelContinuation = levelCont!
    }

    // MARK: - Gating Control (Echo Protection)

    /// Enables audio gating for echo protection
    ///
    /// When gating is enabled, only audio chunks with RMS level above the threshold
    /// will be forwarded. This helps filter out echo while allowing genuine speech.
    ///
    /// - Parameter threshold: RMS level threshold (0.0-1.0)
    public func enableGating(threshold: Float) {
        let clampedThreshold = min(max(threshold, 0.0), 1.0)
        gatingState.withLock { state in
            state.isEnabled = true
            state.threshold = clampedThreshold
        }
    }

    /// Disables audio gating
    public func disableGating() {
        gatingState.withLock { state in
            state.isEnabled = false
            state.threshold = 0.0
        }
    }

    // MARK: - Capture Control

    /// Starts capturing audio from the microphone
    /// - Parameter onAudioChunk: Callback for each audio chunk (base64-encoded)
    /// - Throws: RealtimeError if capture fails to start
    public func start(
        onAudioChunk: @escaping @Sendable (String) async -> Void
    ) async throws {
        guard !isCapturing else {
            throw RealtimeError.audioCaptureFailed(
                NSError(domain: "AudioCapture", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Already capturing"
                ])
            )
        }

        // Request microphone permission
        #if os(iOS)
        let permissionGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard permissionGranted else {
            throw RealtimeError.audioCaptureFailed(
                NSError(domain: "AudioCapture", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Microphone permission denied"
                ])
            )
        }
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
            #endif

            // Create audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            // Get input format
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let sampleRate = Float(inputFormat.sampleRate)

            guard format.makeAVAudioFormat() != nil else {
                throw RealtimeError.unsupportedAudioFormat(format.rawValue)
            }

            // Install tap on input node
            let bufferSize: AVAudioFrameCount = 2048

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
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

                // Yield to stream (always, for visualizations)
                self.audioLevelContinuation.yield(smoothedLevels)

                // Check gating state (thread-safe read)
                let (isGated, gateThreshold) = self.gatingState.withLock { state in
                    (state.isEnabled, state.threshold)
                }

                // If gated and level is below threshold, don't send audio
                if isGated && smoothedLevels.level < gateThreshold {
                    // Audio is below threshold, filter it out (echo protection)
                    return
                }

                // Process audio data for sending
                Task { [weak self, onAudioChunk] in
                    guard let self = self else { return }

                    do {
                        // Convert to target format
                        nonisolated(unsafe) let capturedBuffer = buffer
                        let audioData = try await self.processor.convert(capturedBuffer)

                        // Encode to base64
                        let base64Audio = await self.processor.toBase64(audioData)

                        // Send to callback
                        await onAudioChunk(base64Audio)
                    } catch {
                        // Log error but continue capturing
                    }
                }
            }

            // Start the engine
            try engine.start()

            self.audioEngine = engine
            self.inputNode = inputNode
            self.isCapturing = true

        } catch {
            throw RealtimeError.audioCaptureFailed(error)
        }
    }

    /// Stops capturing audio
    public func stop() {
        guard isCapturing else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        audioEngine = nil
        inputNode = nil
        isCapturing = false

        // Reset levels
        currentLevels.withLock { $0 = .zero }
        audioLevelContinuation.yield(.zero)

        // Reset gating state
        gatingState.withLock { state in
            state.isEnabled = false
            state.threshold = 0.0
        }
    }

    /// Pauses audio capture (stops engine but keeps tap installed)
    /// Note: AVAudioEngine doesn't have pause(), so we stop the engine
    /// The tap remains installed and can be restarted with resume()
    public func pause() {
        // Stop engine but keep tap installed (don't call removeTap)
        // This allows resume() to restart without reinstalling tap
        audioEngine?.stop()
    }

    /// Resumes audio capture
    public func resume() throws {
        guard let engine = audioEngine else {
            throw RealtimeError.audioCaptureFailed(
                NSError(domain: "AudioCapture", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "No audio engine available"
                ])
            )
        }

        if !engine.isRunning {
            // Stop engine first if it's in a bad state
            engine.stop()

            // Restart the engine
            try engine.start()
        }

        // Ensure we're still capturing
        if !isCapturing {
            isCapturing = true
        }
    }

    // MARK: - State

    /// Whether audio is currently being captured
    public var isActive: Bool {
        return isCapturing && (audioEngine?.isRunning ?? false)
    }

    deinit {
        audioLevelContinuation.finish()
    }
}
