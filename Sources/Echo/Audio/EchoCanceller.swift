// EchoCanceller.swift
// Echo - Audio
// Correlation-based acoustic echo canceller

import Foundation
import Accelerate

/// Correlation-based acoustic echo canceller
///
/// Uses cross-correlation between microphone input and known output audio
/// to detect and suppress echo. When the correlation coefficient is high,
/// the input is likely echo; when low, it's genuine user speech.
///
/// This approach is superior to volume-based gating because it detects echo
/// based on waveform pattern matching rather than amplitude, allowing it to:
/// - Detect loud echo (phone near speaker)
/// - Pass through quiet user speech (phone held away)
///
/// - Note: Uses `@unchecked Sendable` because internal state is protected by actor isolation
public actor EchoCanceller {
    // MARK: - Properties
    
    /// Circular buffer of recently played output audio (as Float samples)
    private var referenceBuffer: [Float] = []
    
    /// Maximum reference buffer size in samples
    private let maxReferenceSize: Int
    
    /// Correlation threshold above which audio is considered echo
    private let correlationThreshold: Float
    
    /// Sample rate for delay calculations
    private let sampleRate: Float
    
    /// Minimum delay to search (in samples)
    private let minDelaySamples: Int
    
    /// Maximum delay to search (in samples)
    private let maxDelaySamples: Int
    
    /// Whether canceller is currently active
    private var isActive: Bool = false
    
    /// Configuration used to create this canceller
    public let configuration: EchoCancellerConfiguration
    
    // MARK: - Initialization
    
    /// Creates an echo canceller with the specified configuration
    /// - Parameter configuration: The configuration to use (default: `.default`)
    public init(configuration: EchoCancellerConfiguration = .default) {
        self.configuration = configuration
        self.sampleRate = configuration.sampleRate
        self.maxReferenceSize = Int(configuration.sampleRate * Float(configuration.maxReferenceDurationMs) / 1000)
        self.correlationThreshold = configuration.correlationThreshold
        self.minDelaySamples = Int(configuration.sampleRate * Float(configuration.minDelayMs) / 1000)
        self.maxDelaySamples = Int(configuration.sampleRate * Float(configuration.maxDelayMs) / 1000)
        self.referenceBuffer = []
        self.referenceBuffer.reserveCapacity(maxReferenceSize)
    }
    
    // MARK: - Reference Management
    
    /// Adds output audio samples to the reference buffer
    ///
    /// Call this every time audio is played through the speaker.
    /// The buffer maintains a rolling window of the most recent audio.
    ///
    /// - Parameter samples: Float samples from the output audio (normalized -1.0 to 1.0)
    public func addReference(_ samples: [Float]) {
        guard isActive else { return }
        
        referenceBuffer.append(contentsOf: samples)
        
        // Trim to max size (keep most recent samples)
        if referenceBuffer.count > maxReferenceSize {
            referenceBuffer.removeFirst(referenceBuffer.count - maxReferenceSize)
        }
    }
    
    /// Adds output audio data (PCM16 format) to the reference buffer
    ///
    /// Convenience method that handles PCM16 to Float conversion.
    ///
    /// - Parameter data: Raw PCM16 audio data (what comes from responseAudioDelta)
    public func addReference(pcm16Data data: Data) {
        // Convert PCM16 to Float
        let samples = data.withUnsafeBytes { bytes -> [Float] in
            let int16Buffer = bytes.bindMemory(to: Int16.self)
            return int16Buffer.map { Float($0) / Float(Int16.max) }
        }
        addReference(samples)
    }
    
    /// Clears the reference buffer
    ///
    /// Call this when the assistant stops speaking to reset the state.
    public func clearReference() {
        referenceBuffer.removeAll(keepingCapacity: true)
    }
    
    /// Activates the echo canceller
    ///
    /// When active, the canceller will accept reference audio and perform
    /// echo detection. Call this when the assistant starts speaking.
    public func activate() {
        isActive = true
    }
    
    /// Deactivates the echo canceller and clears the buffer
    ///
    /// Call this when the assistant stops speaking. The buffer is cleared
    /// to prevent stale audio from causing false positives.
    public func deactivate() {
        isActive = false
        clearReference()
    }
    
    // MARK: - Echo Detection
    
    /// Checks if input audio is likely echo
    ///
    /// Uses normalized cross-correlation to compare input with recently played audio.
    /// Searches across a range of delays to account for room acoustics.
    ///
    /// - Parameter inputSamples: Float samples from the microphone (normalized -1.0 to 1.0)
    /// - Returns: `true` if high correlation detected (input is echo), `false` otherwise
    public func isEcho(_ inputSamples: [Float]) -> Bool {
        guard isActive, !referenceBuffer.isEmpty else { return false }
        guard inputSamples.count >= 256 else { return false } // Need enough samples
        
        let maxCorrelation = computeMaxCorrelation(
            input: inputSamples,
            reference: referenceBuffer
        )
        
        return maxCorrelation > correlationThreshold
    }
    
    /// Checks if PCM16 audio data is likely echo
    ///
    /// Convenience method that handles PCM16 to Float conversion.
    ///
    /// - Parameter data: Raw PCM16 audio data from microphone
    /// - Returns: `true` if high correlation detected (input is echo)
    public func isEcho(pcm16Data data: Data) -> Bool {
        let samples = data.withUnsafeBytes { bytes -> [Float] in
            let int16Buffer = bytes.bindMemory(to: Int16.self)
            return int16Buffer.map { Float($0) / Float(Int16.max) }
        }
        return isEcho(samples)
    }
    
    /// Gets the correlation score for input audio
    ///
    /// Returns the actual correlation value rather than a boolean.
    /// Useful for debugging or adaptive thresholding.
    ///
    /// - Parameter inputSamples: Float samples from the microphone
    /// - Returns: Maximum correlation coefficient found (0.0 to 1.0)
    public func correlationScore(_ inputSamples: [Float]) -> Float {
        guard isActive, !referenceBuffer.isEmpty else { return 0 }
        guard inputSamples.count >= 256 else { return 0 }
        
        return computeMaxCorrelation(
            input: inputSamples,
            reference: referenceBuffer
        )
    }
    
    // MARK: - Correlation Computation
    
    /// Computes maximum normalized cross-correlation across the delay range
    ///
    /// Searches through delays from `minDelaySamples` to `maxDelaySamples`,
    /// stepping by 16 samples for efficiency.
    ///
    /// - Parameters:
    ///   - input: Input audio samples
    ///   - reference: Reference (output) audio buffer
    /// - Returns: Maximum correlation coefficient found
    private func computeMaxCorrelation(input: [Float], reference: [Float]) -> Float {
        var maxCorrelation: Float = 0
        
        // Search through delay range, stepping by 16 samples for efficiency
        // At 24kHz, 16 samples ≈ 0.67ms resolution
        let stepSize = 16
        for delay in stride(from: minDelaySamples, through: maxDelaySamples, by: stepSize) {
            let correlation = normalizedCorrelation(
                input: input,
                reference: reference,
                delay: delay
            )
            maxCorrelation = max(maxCorrelation, correlation)
            
            // Early exit if we find strong correlation
            if maxCorrelation > correlationThreshold + 0.1 {
                break
            }
        }
        
        return maxCorrelation
    }
    
    /// Computes normalized cross-correlation at a specific delay using vDSP
    ///
    /// The normalized correlation coefficient ranges from -1 to +1:
    /// - +1.0 = Identical waveforms (perfect echo)
    /// - 0.0 = Completely unrelated (user speech)
    /// - -1.0 = Inverted waveform (phase-flipped echo)
    ///
    /// We use `abs()` to catch both positive and negative correlations.
    ///
    /// - Parameters:
    ///   - input: Input audio samples
    ///   - reference: Reference audio buffer
    ///   - delay: Delay offset in samples
    /// - Returns: Absolute normalized correlation coefficient (0.0 to 1.0)
    private func normalizedCorrelation(
        input: [Float],
        reference: [Float],
        delay: Int
    ) -> Float {
        // Align the input with the reference at the given delay
        // Echo in input corresponds to reference played `delay` samples ago
        let refEnd = reference.count - delay
        guard refEnd > 0 else { return 0 }
        
        let length = min(input.count, refEnd)
        guard length > 256 else { return 0 }
        
        // Get aligned segments
        let refStart = refEnd - length
        
        // Extract segments for correlation
        let inputSegment = Array(input.prefix(length))
        let refSegment = Array(reference[refStart..<refEnd])
        
        // Cross-correlation: sum(input * ref)
        var correlation: Float = 0
        vDSP_dotpr(inputSegment, 1, refSegment, 1, &correlation, vDSP_Length(length))
        
        // Energies for normalization
        var inputEnergy: Float = 0
        var refEnergy: Float = 0
        vDSP_dotpr(inputSegment, 1, inputSegment, 1, &inputEnergy, vDSP_Length(length))
        vDSP_dotpr(refSegment, 1, refSegment, 1, &refEnergy, vDSP_Length(length))
        
        // Normalized correlation coefficient [-1, 1]
        let denominator = sqrt(inputEnergy * refEnergy)
        guard denominator > 1e-10 else { return 0 }
        
        // Return absolute value to catch both positive and negative correlations
        return abs(correlation / denominator)
    }
    
    // MARK: - State
    
    /// Whether the canceller is currently active
    public var isCurrentlyActive: Bool {
        isActive
    }
    
    /// Whether the canceller currently has reference audio
    public var hasReference: Bool {
        !referenceBuffer.isEmpty
    }
    
    /// Current reference buffer size in samples
    public var referenceBufferSize: Int {
        referenceBuffer.count
    }
    
    /// Current reference buffer duration in milliseconds
    public var referenceDurationMs: Int {
        Int(Float(referenceBuffer.count) / sampleRate * 1000)
    }
}

