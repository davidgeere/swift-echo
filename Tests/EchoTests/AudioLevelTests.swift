// AudioLevelTests.swift
// Echo Tests
// Tests for audio level calculation and PCM16 normalization

import Testing
import Foundation
@testable import Echo

@Suite("AudioLevel Tests")
struct AudioLevelTests {

    // MARK: - Helper to convert samples to Data

    private func makeData(from samples: [Int16]) -> Data {
        var mutableSamples = samples
        return Data(bytes: &mutableSamples, count: samples.count * 2)
    }

    // MARK: - RMS Level Tests

    @Test("RMS level of silence is zero")
    func rmsLevelOfSilence() {
        let data = makeData(from: [0, 0, 0, 0, 0, 0, 0, 0])
        let level = AudioLevel.calculate(from: data)
        #expect(level == 0.0)
    }

    @Test("RMS level of full-scale signal is high")
    func rmsLevelOfFullScale() {
        // All samples at Int16.max
        let samples = [Int16](repeating: Int16.max, count: 100)
        let data = makeData(from: samples)
        let level = AudioLevel.calculate(from: data)
        // Note: calculate() scales by 2x, so should be close to 1.0
        #expect(level > 0.9 && level <= 1.0)
    }

    @Test("RMS level handles negative values correctly")
    func rmsLevelWithNegativeValues() {
        // All samples at Int16.min - should produce valid normalized level
        let samples = [Int16](repeating: Int16.min, count: 100)
        let data = makeData(from: samples)
        let level = AudioLevel.calculate(from: data)
        // Should be a valid level (1.0 since all samples are at max magnitude)
        #expect(level > 0.9 && level <= 1.0, "RMS of Int16.min samples should be high")
    }

    @Test("RMS level is within valid range for any input")
    func rmsLevelValidRange() {
        // Mixed samples including extremes
        let samples: [Int16] = [Int16.min, -16384, 0, 16384, Int16.max]
        let data = makeData(from: samples)
        let level = AudioLevel.calculate(from: data)
        #expect(level >= 0.0 && level <= 1.0, "RMS level must be in [0, 1] range")
    }

    // MARK: - Peak Level Tests

    @Test("Peak level of silence is zero")
    func peakLevelOfSilence() {
        let data = makeData(from: [0, 0, 0, 0, 0, 0, 0, 0])
        let level = AudioLevel.calculatePeak(from: data)
        #expect(level == 0.0)
    }

    @Test("Peak level of full-scale positive signal")
    func peakLevelFullScalePositive() {
        let samples: [Int16] = [0, 100, Int16.max, 100, 0]
        let data = makeData(from: samples)
        let level = AudioLevel.calculatePeak(from: data)
        // Int16.max / 32768.0 ≈ 0.99997
        #expect(level > 0.99 && level <= 1.0)
    }

    @Test("Peak level of full-scale negative signal")
    func peakLevelFullScaleNegative() {
        let samples: [Int16] = [0, -100, Int16.min, -100, 0]
        let data = makeData(from: samples)
        let level = AudioLevel.calculatePeak(from: data)
        // abs(Int16.min) / 32768.0 = 1.0 exactly
        #expect(level == 1.0, "Peak level of Int16.min should be exactly 1.0")
    }

    @Test("Peak level is within valid range for any input")
    func peakLevelValidRange() {
        let samples: [Int16] = [Int16.min, -16384, 0, 16384, Int16.max]
        let data = makeData(from: samples)
        let level = AudioLevel.calculatePeak(from: data)
        #expect(level >= 0.0 && level <= 1.0, "Peak level must be in [0, 1] range")
    }

    // MARK: - PCM16 Normalization Tests

    @Test("PCM16 normalization uses 32768.0 divisor")
    func pcm16NormalizationDivisor() {
        // Verify the normalization math is correct
        // Int16.min (-32768) / 32768.0 = -1.0 (exact)
        let minNormalized = Double(Int16.min) / 32768.0
        #expect(minNormalized == -1.0, "Int16.min should normalize to exactly -1.0")

        // Int16.max (32767) / 32768.0 ≈ 0.99997
        let maxNormalized = Double(Int16.max) / 32768.0
        #expect(maxNormalized > 0.99 && maxNormalized < 1.0)

        // Both should be in valid range
        #expect(minNormalized >= -1.0 && minNormalized <= 1.0)
        #expect(maxNormalized >= -1.0 && maxNormalized <= 1.0)
    }

    @Test("Incorrect Int16.max divisor produces out-of-range values")
    func incorrectDivisorOutOfRange() {
        // Using Int16.max (32767) as divisor is incorrect
        let wrongMinNormalized = Double(Int16.min) / Double(Int16.max)
        #expect(wrongMinNormalized < -1.0, "Wrong divisor produces out-of-range value for Int16.min")
        
        // The correct divisor (32768.0) should keep values in range
        let correctMinNormalized = Double(Int16.min) / 32768.0
        #expect(correctMinNormalized == -1.0, "Correct divisor keeps Int16.min at exactly -1.0")
    }

    @Test("RMS level with mixed signal")
    func rmsLevelMixedSignal() {
        // Create a signal with known values
        let samples: [Int16] = [1000, -1000, 2000, -2000, 3000, -3000]
        let data = makeData(from: samples)
        let level = AudioLevel.calculate(from: data)

        // Should produce valid level
        #expect(level > 0.0 && level < 1.0)
    }

    @Test("Empty data produces zero level")
    func emptyInput() {
        let emptyData = Data()
        let rms = AudioLevel.calculate(from: emptyData)
        let peak = AudioLevel.calculatePeak(from: emptyData)

        #expect(rms == 0.0)
        #expect(peak == 0.0)
    }

    // MARK: - Scaling Tests

    @Test("Linear scaling returns same value")
    func linearScaling() {
        let value = 0.5
        let scaled = AudioLevel.scale(value, mode: .linear)
        #expect(scaled == value)
    }

    @Test("Logarithmic scaling handles silence")
    func logarithmicScalingHandlesSilence() {
        let scaled = AudioLevel.scale(0.0, mode: .logarithmic)
        #expect(scaled == 0.0)
    }

    @Test("Exponential scaling squares the value")
    func exponentialScaling() {
        let value = 0.5
        let scaled = AudioLevel.scale(value, mode: .exponential)
        #expect(scaled == 0.25, "0.5^2 should equal 0.25")
    }

    // MARK: - Smoother Tests

    @Test("Smoother starts at zero")
    func smootherStartsAtZero() async {
        let smoother = AudioLevel.Smoother()
        let level = await smoother.level
        #expect(level == 0.0)
    }

    @Test("Smoother updates towards new value")
    func smootherUpdates() async {
        let smoother = AudioLevel.Smoother(smoothingFactor: 0.5)
        
        // Update with 1.0
        let updated = await smoother.update(with: 1.0)
        
        // With 0.5 smoothing: 0.5 * 0.0 + 0.5 * 1.0 = 0.5
        #expect(updated == 0.5)
    }

    @Test("Smoother resets to zero")
    func smootherResets() async {
        let smoother = AudioLevel.Smoother()
        
        _ = await smoother.update(with: 0.8)
        await smoother.reset()
        
        let level = await smoother.level
        #expect(level == 0.0)
    }
}
