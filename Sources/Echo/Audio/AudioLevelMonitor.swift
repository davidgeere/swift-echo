// AudioLevelMonitor.swift
// Echo - Audio
// Transport-agnostic audio level monitoring for visualization

@preconcurrency import AVFoundation
import Foundation
import os

/// Monitors audio input/output levels for visualization (transport-agnostic)
///
/// This actor provides a unified interface for audio level monitoring that works
/// with both WebSocket and WebRTC transports:
///
/// - **Input levels**: Always from hardware microphone tap (shared by both transports)
/// - **Output levels**: Fed externally via `processOutputAudio()` from audio delta events
///
/// This design ensures the same events (`inputLevelsChanged`, `outputLevelsChanged`)
/// are emitted regardless of transport, keeping the consumer agnostic of the source.
public actor AudioLevelMonitor {
    // MARK: - Properties
    
    private var engine: AVAudioEngine?
    private var isMonitoring = false
    
    /// Frequency analyzer for FFT-based level analysis
    private let inputAnalyzer = FrequencyAnalyzer()
    private let outputAnalyzer = FrequencyAnalyzer()
    
    /// Smoothing factor for level transitions (0.0-1.0, higher = faster response)
    private let smoothingFactor: Float = 0.3
    
    /// Sample rate for output audio analysis (default: 24kHz for OpenAI Realtime)
    private let outputSampleRate: Float = 24000.0
    
    /// Current smoothed input levels (thread-safe via lock)
    private let currentInputLevels = OSAllocatedUnfairLock(initialState: AudioLevels.zero)
    
    /// Current smoothed output levels (thread-safe via lock)
    private let currentOutputLevels = OSAllocatedUnfairLock(initialState: AudioLevels.zero)
    
    /// Stream of input audio levels for visualization
    public let inputLevelStream: AsyncStream<AudioLevels>
    private let inputLevelContinuation: AsyncStream<AudioLevels>.Continuation
    
    /// Stream of output audio levels for visualization
    public let outputLevelStream: AsyncStream<AudioLevels>
    private let outputLevelContinuation: AsyncStream<AudioLevels>.Continuation
    
    // MARK: - Initialization
    
    public init() {
        var inputCont: AsyncStream<AudioLevels>.Continuation?
        self.inputLevelStream = AsyncStream { continuation in
            inputCont = continuation
        }
        self.inputLevelContinuation = inputCont!
        
        var outputCont: AsyncStream<AudioLevels>.Continuation?
        self.outputLevelStream = AsyncStream { continuation in
            outputCont = continuation
        }
        self.outputLevelContinuation = outputCont!
    }
    
    // MARK: - Public Methods
    
    /// Starts monitoring hardware audio input levels
    ///
    /// - Note: Only monitors INPUT (microphone). Output levels are fed via `processOutputAudio()`.
    /// - Throws: Error if the audio engine cannot be started
    public func start() async throws {
        guard !isMonitoring else { return }
        
        let engine = AVAudioEngine()
        
        // Get the input node (microphone) - this is shared hardware, works for both transports
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let inputSampleRate = Float(inputFormat.sampleRate)
        
        // Install tap on input node for microphone levels
        if inputFormat.channelCount > 0 && inputFormat.sampleRate > 0 {
            // DEBUG: Track how often we log (don't spam)
            var inputLogCounter = 0
            
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                
                // Extract samples synchronously on audio thread
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                
                // Calculate levels using frequency analyzer
                let newLevels = self.inputAnalyzer.analyze(samples: samples, sampleRate: inputSampleRate)
                
                // Apply smoothing
                let smoothedLevels = self.currentInputLevels.withLock { current in
                    let smoothed = newLevels.smoothed(from: current, factor: self.smoothingFactor)
                    current = smoothed
                    return smoothed
                }
                
                // DEBUG: Log input levels occasionally (every 50th callback to avoid spam)
                inputLogCounter += 1
                if inputLogCounter % 50 == 0 {
                    print("[DEBUG-LEVELS] 🎤 Input levels - level: \(String(format: "%.3f", smoothedLevels.level)), low: \(String(format: "%.3f", smoothedLevels.low)), mid: \(String(format: "%.3f", smoothedLevels.mid)), high: \(String(format: "%.3f", smoothedLevels.high))")
                }
                
                // Yield to stream
                Task { [weak self] in
                    self?.inputLevelContinuation.yield(smoothedLevels)
                }
            }
        }
        
        // NOTE: We do NOT tap output here. Output levels are fed via processOutputAudio()
        // This is because WebRTC doesn't route through AVAudioEngine's mixer.
        
        // Prepare and start the engine (required even for input-only)
        engine.prepare()
        try engine.start()
        
        self.engine = engine
        self.isMonitoring = true
        
        print("[AudioLevelMonitor] ✅ Started monitoring (input: hardware mic, output: fed externally)")
    }
    
    /// Processes output audio data and emits output level events
    ///
    /// This should be called whenever audio is being played/sent to the speaker,
    /// regardless of transport (WebSocket or WebRTC). Both transports receive
    /// `response.audio.delta` events which can be decoded and passed here.
    ///
    /// - Parameter pcm16Data: Raw PCM16 audio data (decoded from base64 audio delta)
    public func processOutputAudio(pcm16Data: Data) {
        guard isMonitoring else {
            print("[DEBUG-LEVELS] ⚠️ processOutputAudio called but not monitoring")
            return
        }
        
        // Convert PCM16 to Float samples
        let samples: [Float] = pcm16Data.withUnsafeBytes { bytes in
            let int16Buffer = bytes.bindMemory(to: Int16.self)
            return int16Buffer.map { Float($0) / 32768.0 }
        }
        
        guard !samples.isEmpty else {
            print("[DEBUG-LEVELS] ⚠️ processOutputAudio: no samples after conversion")
            return
        }
        
        // Calculate levels using frequency analyzer
        let newLevels = outputAnalyzer.analyze(samples: samples, sampleRate: outputSampleRate)
        
        // Apply smoothing
        let smoothedLevels = currentOutputLevels.withLock { current in
            let smoothed = newLevels.smoothed(from: current, factor: smoothingFactor)
            current = smoothed
            return smoothed
        }
        
        // DEBUG: Log output levels
        print("[DEBUG-LEVELS] 🔊 Output levels - level: \(String(format: "%.3f", smoothedLevels.level)), low: \(String(format: "%.3f", smoothedLevels.low)), mid: \(String(format: "%.3f", smoothedLevels.mid)), high: \(String(format: "%.3f", smoothedLevels.high))")
        
        // Yield to stream
        outputLevelContinuation.yield(smoothedLevels)
    }
    
    /// Processes output audio from base64-encoded audio (convenience method)
    ///
    /// - Parameter base64Audio: Base64-encoded PCM16 audio data
    public func processOutputAudio(base64Audio: String) {
        guard let data = Data(base64Encoded: base64Audio) else { return }
        processOutputAudio(pcm16Data: data)
    }
    
    /// Stops monitoring audio levels
    public func stop() async {
        guard isMonitoring else { return }
        
        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        
        engine = nil
        isMonitoring = false
        
        // Reset levels to zero
        currentInputLevels.withLock { $0 = .zero }
        currentOutputLevels.withLock { $0 = .zero }
        
        // Emit zero levels
        inputLevelContinuation.yield(.zero)
        outputLevelContinuation.yield(.zero)
        
        print("[AudioLevelMonitor] ✅ Stopped monitoring audio levels")
    }
    
    /// Whether the monitor is currently running
    public var isActive: Bool {
        isMonitoring
    }
    
    /// Current input levels (for polling)
    public var currentInputLevel: AudioLevels {
        currentInputLevels.withLock { $0 }
    }
    
    /// Current output levels (for polling)
    public var currentOutputLevel: AudioLevels {
        currentOutputLevels.withLock { $0 }
    }
}

