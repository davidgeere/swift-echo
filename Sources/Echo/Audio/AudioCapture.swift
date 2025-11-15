// AudioCapture.swift
// Echo - Audio
// Microphone audio capture using AVFoundation

import Foundation
@preconcurrency import AVFoundation

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

    /// Audio level stream for visualizations
    public let audioLevelStream: AsyncStream<Double>
    private let audioLevelContinuation: AsyncStream<Double>.Continuation

    // MARK: - Initialization

    /// Creates an audio capture instance
    /// - Parameter format: The target audio format (default: .pcm16)
    public init(format: AudioFormat = .pcm16) {
        self.format = format
        self.processor = AudioProcessor(targetFormat: format)

        var levelCont: AsyncStream<Double>.Continuation?
        self.audioLevelStream = AsyncStream { continuation in
            levelCont = continuation
        }
        self.audioLevelContinuation = levelCont!
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

            guard format.makeAVAudioFormat() != nil else {
                throw RealtimeError.unsupportedAudioFormat(format.rawValue)
            }

            // Install tap on input node
            let bufferSize: AVAudioFrameCount = 1024

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
                // Use unstructured Task isolated to the actor to avoid data race
                Task { [weak self, onAudioChunk] in
                    guard let self = self else { return }

                    do {
                        // Calculate audio level
                        // Note: AVAudioPCMBuffer is not Sendable, but we're using it immediately in a controlled manner
                        nonisolated(unsafe) let capturedBuffer = buffer
                        let level = AudioLevel.calculate(from: capturedBuffer)
                        self.audioLevelContinuation.yield(level)

                        // Convert to target format
                        let audioData = try await self.processor.convert(capturedBuffer)

                        // Encode to base64
                        let base64Audio = await self.processor.toBase64(audioData)

                        // Send to callback
                        await onAudioChunk(base64Audio)
                    } catch {
                        // Log error but continue capturing
                        print("Audio conversion error: \(error)")
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

        audioLevelContinuation.yield(0.0)
    }

    /// Pauses audio capture (keeps engine running)
    public func pause() {
        audioEngine?.pause()
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
            try engine.start()
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
