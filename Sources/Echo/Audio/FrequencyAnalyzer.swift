// FrequencyAnalyzer.swift
// Echo - Audio
// FFT-based frequency analysis for audio level monitoring

import Accelerate
import AVFoundation

/// Performs FFT analysis on audio buffers to extract frequency band energy levels
///
/// Uses Apple's Accelerate framework (vDSP) for high-performance FFT processing.
/// Analyzes audio into three frequency bands: low, mid, and high.
///
/// - Note: This class uses `@unchecked Sendable` because `FFTSetup` is an opaque pointer
///   that is safe to use across threads when the instance is not mutated after initialization.
final class FrequencyAnalyzer: @unchecked Sendable {
    /// FFT size - must be power of 2. 2048 provides good frequency resolution
    private let fftSize: Int = 2048
    
    /// Log2 of FFT size, required by vDSP
    private let log2n: vDSP_Length
    
    /// FFT setup object for vDSP operations
    private let fftSetup: FFTSetup
    
    /// Frequency band boundaries in Hz
    private let lowMaxFrequency: Float = 250
    private let midMaxFrequency: Float = 4000
    
    /// Initializes the frequency analyzer with FFT setup
    ///
    /// - Note: FFT setup failure is a system-level error that should not occur
    ///         under normal circumstances. If it fails, it indicates a critical
    ///         system resource issue.
    init() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Failed to create FFT setup - this indicates a critical system resource issue")
        }
        fftSetup = setup
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    /// Analyzes audio samples and returns frequency band levels
    /// - Parameters:
    ///   - samples: Array of audio samples to analyze
    ///   - sampleRate: The sample rate of the audio (e.g., 44100, 48000)
    /// - Returns: AudioLevels with overall level and frequency band energies
    func analyze(samples: [Float], sampleRate: Float) -> AudioLevels {
        guard !samples.isEmpty else { return .zero }
        
        // Calculate RMS for overall level
        let level = calculateRMS(samples: samples)
        
        // Perform FFT analysis for frequency bands
        let bands = performFFT(samples: samples, sampleRate: sampleRate)
        
        return AudioLevels(
            level: level,
            low: bands.low,
            mid: bands.mid,
            high: bands.high
        )
    }
    
    /// Calculates RMS (root mean square) amplitude
    private func calculateRMS(samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        // Scale to 0-1 range (adjust multiplier for sensitivity)
        return min(1.0, rms * 25)
    }
    
    /// Performs FFT and extracts frequency band energies
    private func performFFT(
        samples: [Float],
        sampleRate: Float
    ) -> (low: Float, mid: Float, high: Float) {
        let frameCount = min(samples.count, fftSize)
        
        // Prepare input with Hann window to reduce spectral leakage
        var windowedData = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Copy and window the input data
        for i in 0..<frameCount {
            windowedData[i] = samples[i] * window[i]
        }
        
        // Split complex arrays for FFT
        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)
        
        // Pack data into split complex format
        windowedData.withUnsafeBufferPointer { inputBuffer in
            realPart.withUnsafeMutableBufferPointer { realBuffer in
                imagPart.withUnsafeMutableBufferPointer { imagBuffer in
                    var splitComplex = DSPSplitComplex(
                        realp: realBuffer.baseAddress!,
                        imagp: imagBuffer.baseAddress!
                    )
                    
                    // Convert to split complex format
                    inputBuffer.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: fftSize / 2
                    ) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                    
                    // Perform forward FFT
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
        }
        
        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        realPart.withUnsafeMutableBufferPointer { realBuffer in
            imagPart.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imagBuffer.baseAddress!
                )
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // Calculate bin boundaries based on sample rate
        let binFrequencyWidth = sampleRate / Float(fftSize)
        let lowMaxBin = Int(lowMaxFrequency / binFrequencyWidth)
        let midMaxBin = Int(midMaxFrequency / binFrequencyWidth)
        let highMaxBin = fftSize / 2
        
        // Validate bin boundaries - sample rate must be high enough for meaningful separation
        guard lowMaxBin < midMaxBin && midMaxBin < highMaxBin else {
            // Sample rate too low for meaningful frequency band separation
            return (low: 0, mid: 0, high: 0)
        }
        
        // Sum energy in each band.
        // Note: Bin 0 contains the DC component (average signal level), not frequency content,
        // so we intentionally skip it by starting from bin 1.
        let lowEnergy = sumBandEnergy(magnitudes: magnitudes, from: 1, to: lowMaxBin)
        let midEnergy = sumBandEnergy(magnitudes: magnitudes, from: lowMaxBin, to: midMaxBin)
        let highEnergy = sumBandEnergy(magnitudes: magnitudes, from: midMaxBin, to: highMaxBin)
        
        // Normalize to 0-1 range
        let scaleFactor: Float = 0.00001 // Adjust for sensitivity
        
        return (
            low: min(1.0, sqrt(lowEnergy * scaleFactor)),
            mid: min(1.0, sqrt(midEnergy * scaleFactor)),
            high: min(1.0, sqrt(highEnergy * scaleFactor))
        )
    }
    
    /// Sums the energy in a frequency band
    private func sumBandEnergy(magnitudes: [Float], from: Int, to: Int) -> Float {
        guard from < to, from >= 0, to <= magnitudes.count else { return 0 }
        
        var sum: Float = 0
        vDSP_sve(
            Array(magnitudes[from..<to]),
            1,
            &sum,
            vDSP_Length(to - from)
        )
        return sum
    }
}

