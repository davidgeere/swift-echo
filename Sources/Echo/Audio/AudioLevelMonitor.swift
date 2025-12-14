// AudioLevelMonitor.swift
// Echo - Audio
// Hardware-level audio monitoring for visualization (transport-agnostic)

@preconcurrency import AVFoundation
import Foundation
import os

/// Monitors hardware audio input/output levels for visualization
///
/// This actor monitors the actual hardware audio levels (microphone and speaker)
/// independently of the transport mechanism (WebSocket or WebRTC). This provides
/// consistent level data for UI visualizations regardless of how audio is being
/// captured or played.
///
/// - Note: This uses AVAudioEngine taps on the hardware nodes, which observes
///   but does not interfere with the audio flowing through those nodes.
public actor AudioLevelMonitor {
    // MARK: - Properties
    
    private var engine: AVAudioEngine?
    private var isMonitoring = false
    
    /// Frequency analyzer for FFT-based level analysis
    private let inputAnalyzer = FrequencyAnalyzer()
    private let outputAnalyzer = FrequencyAnalyzer()
    
    /// Smoothing factor for level transitions (0.0-1.0, higher = faster response)
    private let smoothingFactor: Float = 0.3
    
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
    
    /// Starts monitoring hardware audio levels
    ///
    /// - Throws: Error if the audio engine cannot be started
    public func start() async throws {
        guard !isMonitoring else { return }
        
        let engine = AVAudioEngine()
        
        // Get the input node (microphone)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let inputSampleRate = Float(inputFormat.sampleRate)
        
        // Install tap on input node for microphone levels
        if inputFormat.channelCount > 0 && inputFormat.sampleRate > 0 {
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
                
                // Yield to stream
                Task { [weak self] in
                    self?.inputLevelContinuation.yield(smoothedLevels)
                }
            }
        }
        
        // Get the output node (we need to connect something to enable the mixer)
        // We'll use the main mixer node which aggregates all output
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let outputSampleRate = Float(outputFormat.sampleRate)
        
        // Install tap on main mixer for output levels
        if outputFormat.channelCount > 0 && outputFormat.sampleRate > 0 {
            mainMixer.installTap(onBus: 0, bufferSize: 2048, format: outputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                
                // Extract samples synchronously on audio thread
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                
                // Calculate levels using frequency analyzer
                let newLevels = self.outputAnalyzer.analyze(samples: samples, sampleRate: outputSampleRate)
                
                // Apply smoothing
                let smoothedLevels = self.currentOutputLevels.withLock { current in
                    let smoothed = newLevels.smoothed(from: current, factor: self.smoothingFactor)
                    current = smoothed
                    return smoothed
                }
                
                // Yield to stream
                Task { [weak self] in
                    self?.outputLevelContinuation.yield(smoothedLevels)
                }
            }
        }
        
        // Prepare and start the engine
        engine.prepare()
        try engine.start()
        
        self.engine = engine
        self.isMonitoring = true
        
        print("[AudioLevelMonitor] ✅ Started monitoring hardware audio levels")
    }
    
    /// Stops monitoring hardware audio levels
    public func stop() async {
        guard isMonitoring else { return }
        
        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.mainMixerNode.removeTap(onBus: 0)
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
        
        print("[AudioLevelMonitor] ✅ Stopped monitoring hardware audio levels")
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

