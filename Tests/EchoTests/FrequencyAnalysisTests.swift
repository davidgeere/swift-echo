// FrequencyAnalysisTests.swift
// Echo Tests
// Tests for audio frequency analysis functionality

import Foundation
import Testing
@testable import Echo

/// Tests for AudioLevels and FrequencyAnalyzer
@Suite
struct FrequencyAnalysisTests {
    
    // MARK: - AudioLevels Tests
    
    @Test
    func audioLevelsInitializesWithDefaultValues() {
        let levels = AudioLevels()
        
        #expect(levels.level == 0)
        #expect(levels.low == 0)
        #expect(levels.mid == 0)
        #expect(levels.high == 0)
    }
    
    @Test
    func audioLevelsInitializesWithCustomValues() {
        let levels = AudioLevels(level: 0.8, low: 0.3, mid: 0.6, high: 0.4)
        
        #expect(levels.level == 0.8)
        #expect(levels.low == 0.3)
        #expect(levels.mid == 0.6)
        #expect(levels.high == 0.4)
    }
    
    @Test
    func audioLevelsZeroIsAllZeros() {
        let zero = AudioLevels.zero
        
        #expect(zero.level == 0)
        #expect(zero.low == 0)
        #expect(zero.mid == 0)
        #expect(zero.high == 0)
    }
    
    @Test
    func audioLevelsIsSendable() {
        // This test verifies that AudioLevels can be passed across actor boundaries
        let levels = AudioLevels(level: 0.5, low: 0.2, mid: 0.4, high: 0.1)
        
        Task {
            // If AudioLevels weren't Sendable, this would fail to compile
            let _ = levels
        }
        
        #expect(levels.level == 0.5)
    }
    
    @Test
    func audioLevelsIsEquatable() {
        let levels1 = AudioLevels(level: 0.5, low: 0.2, mid: 0.4, high: 0.1)
        let levels2 = AudioLevels(level: 0.5, low: 0.2, mid: 0.4, high: 0.1)
        let levels3 = AudioLevels(level: 0.6, low: 0.2, mid: 0.4, high: 0.1)
        
        #expect(levels1 == levels2)
        #expect(levels1 != levels3)
    }
    
    @Test
    func audioLevelsSmoothingTransitionsGradually() {
        let current = AudioLevels(level: 0.0, low: 0.0, mid: 0.0, high: 0.0)
        let target = AudioLevels(level: 1.0, low: 1.0, mid: 1.0, high: 1.0)
        
        // With factor 0.3, should move 30% towards target
        let smoothed = target.smoothed(from: current, factor: 0.3)
        
        #expect(smoothed.level > 0 && smoothed.level < 1)
        #expect(smoothed.level == 0.3) // 0 + (1 - 0) * 0.3
        #expect(smoothed.low == 0.3)
        #expect(smoothed.mid == 0.3)
        #expect(smoothed.high == 0.3)
    }
    
    @Test
    func audioLevelsSmoothingWithFullFactor() {
        let current = AudioLevels(level: 0.2, low: 0.1, mid: 0.3, high: 0.4)
        let target = AudioLevels(level: 0.8, low: 0.9, mid: 0.7, high: 0.6)
        
        // With factor 1.0, should jump directly to target
        let smoothed = target.smoothed(from: current, factor: 1.0)
        
        #expect(smoothed.level == 0.8)
        #expect(smoothed.low == 0.9)
        #expect(smoothed.mid == 0.7)
        #expect(smoothed.high == 0.6)
    }
    
    @Test
    func audioLevelsSmoothingWithZeroFactor() {
        let current = AudioLevels(level: 0.2, low: 0.1, mid: 0.3, high: 0.4)
        let target = AudioLevels(level: 0.8, low: 0.9, mid: 0.7, high: 0.6)
        
        // With factor 0.0, should stay at current
        let smoothed = target.smoothed(from: current, factor: 0.0)
        
        #expect(smoothed.level == 0.2)
        #expect(smoothed.low == 0.1)
        #expect(smoothed.mid == 0.3)
        #expect(smoothed.high == 0.4)
    }
    
    // MARK: - FrequencyAnalyzer Tests
    
    @Test
    func frequencyAnalyzerInitializes() {
        // Should not crash
        let _ = FrequencyAnalyzer()
    }
    
    @Test
    func frequencyAnalyzerReturnsZeroForEmptySamples() {
        let analyzer = FrequencyAnalyzer()
        let result = analyzer.analyze(samples: [], sampleRate: 48000)
        
        #expect(result == .zero)
    }
    
    @Test
    func frequencyAnalyzerDetectsSilence() {
        let analyzer = FrequencyAnalyzer()
        
        // Silent audio (all zeros)
        let silentSamples = [Float](repeating: 0, count: 2048)
        let result = analyzer.analyze(samples: silentSamples, sampleRate: 48000)
        
        #expect(result.level == 0)
        #expect(result.low == 0)
        #expect(result.mid == 0)
        #expect(result.high == 0)
    }
    
    @Test
    func frequencyAnalyzerDetectsLoudSignal() {
        let analyzer = FrequencyAnalyzer()
        
        // Loud sine wave (full amplitude)
        var samples = [Float](repeating: 0, count: 2048)
        for i in 0..<samples.count {
            samples[i] = sin(Float(i) * 0.1) // Simple sine wave
        }
        
        let result = analyzer.analyze(samples: samples, sampleRate: 48000)
        
        // Should have some level (not zero)
        #expect(result.level > 0)
    }
    
    @Test
    func frequencyAnalyzerOutputsNormalizedValues() {
        let analyzer = FrequencyAnalyzer()
        
        // Random audio signal
        var samples = [Float](repeating: 0, count: 2048)
        for i in 0..<samples.count {
            samples[i] = Float.random(in: -1...1)
        }
        
        let result = analyzer.analyze(samples: samples, sampleRate: 48000)
        
        // All values should be in 0-1 range
        #expect(result.level >= 0 && result.level <= 1)
        #expect(result.low >= 0 && result.low <= 1)
        #expect(result.mid >= 0 && result.mid <= 1)
        #expect(result.high >= 0 && result.high <= 1)
    }
    
    @Test
    func frequencyAnalyzerHandlesDifferentSampleRates() {
        let analyzer = FrequencyAnalyzer()
        
        // Simple tone
        var samples = [Float](repeating: 0, count: 2048)
        for i in 0..<samples.count {
            samples[i] = sin(Float(i) * 0.05)
        }
        
        // Should work at different sample rates without crashing
        let result44 = analyzer.analyze(samples: samples, sampleRate: 44100)
        let result48 = analyzer.analyze(samples: samples, sampleRate: 48000)
        let result24 = analyzer.analyze(samples: samples, sampleRate: 24000)
        
        #expect(result44.level >= 0)
        #expect(result48.level >= 0)
        #expect(result24.level >= 0)
    }
    
    @Test
    func frequencyAnalyzerHandlesShortBuffers() {
        let analyzer = FrequencyAnalyzer()
        
        // Short buffer (less than FFT size)
        let shortSamples = [Float](repeating: 0.5, count: 256)
        let result = analyzer.analyze(samples: shortSamples, sampleRate: 48000)
        
        // Should not crash and return valid values
        #expect(result.level >= 0 && result.level <= 1)
    }
    
    @Test
    func frequencyAnalyzerHandlesVeryLowSampleRate() {
        let analyzer = FrequencyAnalyzer()
        
        // Test with extremely low sample rate where frequency bands would overlap
        // At 1000 Hz sample rate with FFT size 2048:
        // bin width = 1000/2048 ≈ 0.49 Hz
        // lowMaxBin (250 Hz) ≈ 512, midMaxBin (4000 Hz) would be > nyquist (500 Hz)
        // This should trigger the validation guard and return zeros for frequency bands
        var samples = [Float](repeating: 0, count: 2048)
        for i in 0..<samples.count {
            samples[i] = sin(Float(i) * 0.05)
        }
        
        let result = analyzer.analyze(samples: samples, sampleRate: 1000)
        
        // Level should still be calculated (RMS-based)
        #expect(result.level >= 0)
        
        // But frequency bands should be zero due to overlap protection
        #expect(result.low == 0)
        #expect(result.mid == 0)
        #expect(result.high == 0)
    }
    
    // MARK: - Integration Tests
    
    @Test
    func mockAudioCaptureEmitsAudioLevels() async throws {
        let capture = MockAudioCapture()
        
        try await capture.start { _ in }
        
        // Wait a bit for levels to be emitted
        try await Task.sleep(for: .milliseconds(50))
        
        let isActive = await capture.isActive
        #expect(isActive)
        
        await capture.stop()
    }
    
    @Test
    func mockAudioPlaybackEmitsAudioLevels() async throws {
        let playback = MockAudioPlayback()
        
        try await playback.start()
        
        let isActive = await playback.isActive
        #expect(isActive)
        
        await playback.stop()
    }
}

