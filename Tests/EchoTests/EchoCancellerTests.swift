// EchoCancellerTests.swift
// Echo Tests
// Tests for the correlation-based echo canceller

import Foundation
import Testing
@testable import Echo

@Suite("EchoCanceller Tests")
struct EchoCancellerTests {
    // MARK: - Configuration Tests

    @Test("Default configuration has sensible values")
    func defaultConfiguration() {
        let config = EchoCancellerConfiguration.default

        #expect(config.enabled == true)
        #expect(config.sampleRate == 24000)
        #expect(config.correlationThreshold == 0.65)
        #expect(config.maxReferenceDurationMs == 500)
        #expect(config.minDelayMs == 5)
        #expect(config.maxDelayMs == 100)
    }

    @Test("Aggressive configuration has lower threshold")
    func aggressiveConfiguration() {
        let config = EchoCancellerConfiguration.aggressive

        #expect(config.enabled == true)
        #expect(config.correlationThreshold == 0.55)
        #expect(config.maxReferenceDurationMs == 750)
    }

    @Test("Conservative configuration has higher threshold")
    func conservativeConfiguration() {
        let config = EchoCancellerConfiguration.conservative

        #expect(config.enabled == true)
        #expect(config.correlationThreshold == 0.75)
    }

    @Test("Disabled configuration has enabled = false")
    func disabledConfiguration() {
        let config = EchoCancellerConfiguration.disabled

        #expect(config.enabled == false)
    }

    @Test("Custom configuration clamps threshold to valid range")
    func customConfigurationClampsThreshold() {
        let tooHigh = EchoCancellerConfiguration(correlationThreshold: 1.5)
        #expect(tooHigh.correlationThreshold == 1.0)

        let tooLow = EchoCancellerConfiguration(correlationThreshold: -0.5)
        #expect(tooLow.correlationThreshold == 0.0)

        let valid = EchoCancellerConfiguration(correlationThreshold: 0.7)
        #expect(valid.correlationThreshold == 0.7)
    }

    @Test("Configuration enforces minimum values")
    func configurationEnforcesMinimums() {
        let config = EchoCancellerConfiguration(
            maxReferenceDurationMs: 50,  // Below minimum
            minDelayMs: 0,  // Below minimum
            maxDelayMs: 5   // Would be less than minDelayMs + 10
        )

        #expect(config.maxReferenceDurationMs >= 100)
        #expect(config.minDelayMs >= 1)
        #expect(config.maxDelayMs > config.minDelayMs)
    }

    // MARK: - EchoCanceller Initialization Tests

    @Test("EchoCanceller initializes with default configuration")
    func echoCancellerDefaultInit() async {
        let canceller = EchoCanceller()

        let hasRef = await canceller.hasReference
        let isActive = await canceller.isCurrentlyActive

        #expect(hasRef == false)
        #expect(isActive == false)
    }

    @Test("EchoCanceller initializes with custom configuration")
    func echoCancellerCustomInit() async {
        let config = EchoCancellerConfiguration(
            correlationThreshold: 0.7,
            maxReferenceDurationMs: 600
        )
        let canceller = EchoCanceller(configuration: config)

        let storedConfig = await canceller.configuration
        #expect(storedConfig.correlationThreshold == 0.7)
        #expect(storedConfig.maxReferenceDurationMs == 600)
    }

    // MARK: - Activation Tests

    @Test("EchoCanceller activate and deactivate")
    func echoCancellerActivation() async {
        let canceller = EchoCanceller()

        // Initially not active
        var isActive = await canceller.isCurrentlyActive
        #expect(isActive == false)

        // Activate
        await canceller.activate()
        isActive = await canceller.isCurrentlyActive
        #expect(isActive == true)

        // Deactivate
        await canceller.deactivate()
        isActive = await canceller.isCurrentlyActive
        #expect(isActive == false)
    }

    // MARK: - Reference Buffer Tests

    @Test("Reference buffer accepts samples when active")
    func referenceBufferAcceptsSamplesWhenActive() async {
        let canceller = EchoCanceller()

        // Not active - should not add
        await canceller.addReference([1.0, 0.5, -0.5, -1.0])
        var hasRef = await canceller.hasReference
        #expect(hasRef == false)

        // Activate and add
        await canceller.activate()
        await canceller.addReference([1.0, 0.5, -0.5, -1.0])
        hasRef = await canceller.hasReference
        #expect(hasRef == true)

        let size = await canceller.referenceBufferSize
        #expect(size == 4)
    }

    @Test("Reference buffer trims to max size")
    func referenceBufferTrimsToMaxSize() async {
        // Use short buffer for testing
        let config = EchoCancellerConfiguration(
            sampleRate: 1000,
            maxReferenceDurationMs: 100  // 100 samples max
        )
        let canceller = EchoCanceller(configuration: config)
        await canceller.activate()

        // Add 150 samples (more than max)
        let samples = [Float](repeating: 0.5, count: 150)
        await canceller.addReference(samples)

        let size = await canceller.referenceBufferSize
        #expect(size == 100)  // Should be trimmed to max
    }

    @Test("Reference buffer clears on deactivate")
    func referenceBufferClearsOnDeactivate() async {
        let canceller = EchoCanceller()
        await canceller.activate()

        // Add samples
        await canceller.addReference([1.0, 0.5, -0.5, -1.0])
        var hasRef = await canceller.hasReference
        #expect(hasRef == true)

        // Deactivate should clear
        await canceller.deactivate()
        hasRef = await canceller.hasReference
        #expect(hasRef == false)
    }

    @Test("Reference buffer duration is calculated correctly")
    func referenceBufferDuration() async {
        let config = EchoCancellerConfiguration(sampleRate: 1000)  // 1000 Hz for easy math
        let canceller = EchoCanceller(configuration: config)
        await canceller.activate()

        // Add 500 samples at 1000 Hz = 500ms
        let samples = [Float](repeating: 0.5, count: 500)
        await canceller.addReference(samples)

        let durationMs = await canceller.referenceDurationMs
        #expect(durationMs == 500)
    }

    @Test("PCM16 data is converted correctly")
    func pcm16DataConversion() async {
        let canceller = EchoCanceller()
        await canceller.activate()

        // Create PCM16 data (max positive value)
        var int16Value: Int16 = Int16.max
        let data = Data(bytes: &int16Value, count: 2)

        await canceller.addReference(pcm16Data: data)

        let size = await canceller.referenceBufferSize
        #expect(size == 1)
    }

    // MARK: - Echo Detection Tests

    @Test("isEcho returns false when not active")
    func isEchoFalseWhenNotActive() async {
        let canceller = EchoCanceller()

        // Add reference while active
        await canceller.activate()
        await canceller.addReference([Float](repeating: 0.5, count: 1000))
        await canceller.deactivate()

        // Even with buffer (though it's cleared), should return false when not active
        let isEcho = await canceller.isEcho([Float](repeating: 0.5, count: 1000))
        #expect(isEcho == false)
    }

    @Test("isEcho returns false when reference buffer is empty")
    func isEchoFalseWhenNoReference() async {
        let canceller = EchoCanceller()
        await canceller.activate()

        let isEcho = await canceller.isEcho([Float](repeating: 0.5, count: 500))
        #expect(isEcho == false)
    }

    @Test("isEcho returns false for insufficient input samples")
    func isEchoFalseForInsufficientSamples() async {
        let canceller = EchoCanceller()
        await canceller.activate()
        await canceller.addReference([Float](repeating: 0.5, count: 1000))

        // Only 100 samples - less than 256 minimum
        let isEcho = await canceller.isEcho([Float](repeating: 0.5, count: 100))
        #expect(isEcho == false)
    }

    @Test("Identical waveforms are detected as echo")
    func identicalWaveformsAreEcho() async {
        let config = EchoCancellerConfiguration(
            sampleRate: 24000,
            correlationThreshold: 0.65,
            minDelayMs: 0,  // Allow zero delay for testing
            maxDelayMs: 50
        )
        let canceller = EchoCanceller(configuration: config)
        await canceller.activate()

        // Create a recognizable waveform (sine wave)
        let waveform = (0..<2048).map { Float(sin(Double($0) * 0.1)) }

        // Add to reference
        await canceller.addReference(waveform)

        // Check same waveform - should be detected as echo
        let isEcho = await canceller.isEcho(waveform)
        #expect(isEcho == true)
    }

    @Test("Different waveforms are not detected as echo")
    func differentWaveformsAreNotEcho() async {
        let canceller = EchoCanceller()
        await canceller.activate()

        // Add sine wave to reference
        let sineWave = (0..<2048).map { Float(sin(Double($0) * 0.1)) }
        await canceller.addReference(sineWave)

        // Check with different waveform (noise)
        let noise = (0..<2048).map { _ in Float.random(in: -1...1) }
        let isEcho = await canceller.isEcho(noise)
        #expect(isEcho == false)
    }

    @Test("Scaled waveforms are still detected as echo")
    func scaledWaveformsAreEcho() async {
        let config = EchoCancellerConfiguration(
            sampleRate: 24000,
            correlationThreshold: 0.65,
            minDelayMs: 0,
            maxDelayMs: 50
        )
        let canceller = EchoCanceller(configuration: config)
        await canceller.activate()

        // Create a waveform
        let original = (0..<2048).map { Float(sin(Double($0) * 0.1)) }
        await canceller.addReference(original)

        // Scale by 0.5 (simulating quieter echo)
        let scaled = original.map { $0 * 0.5 }

        // Normalized correlation should still detect it
        let isEcho = await canceller.isEcho(scaled)
        #expect(isEcho == true)
    }

    @Test("Correlation score returns valid range")
    func correlationScoreReturnsValidRange() async {
        let canceller = EchoCanceller()
        await canceller.activate()

        let waveform = (0..<2048).map { Float(sin(Double($0) * 0.1)) }
        await canceller.addReference(waveform)

        let score = await canceller.correlationScore(waveform)

        #expect(score >= 0.0)
        #expect(score <= 1.0)
    }

    // MARK: - Echo Protection Configuration Tests

    @Test("EchoProtectionMode enum has correct raw values")
    func echoProtectionModeRawValues() {
        #expect(EchoProtectionMode.threshold.rawValue == "threshold")
        #expect(EchoProtectionMode.correlation.rawValue == "correlation")
        #expect(EchoProtectionMode.hybrid.rawValue == "hybrid")
    }

    @Test("EchoProtectionConfiguration usesThreshold property")
    func echoProtectionUsesThreshold() {
        let thresholdConfig = EchoProtectionConfiguration(mode: .threshold)
        #expect(thresholdConfig.usesThreshold == true)
        #expect(thresholdConfig.usesCorrelation == false)

        let correlationConfig = EchoProtectionConfiguration(mode: .correlation)
        #expect(correlationConfig.usesThreshold == false)
        #expect(correlationConfig.usesCorrelation == true)

        let hybridConfig = EchoProtectionConfiguration(mode: .hybrid)
        #expect(hybridConfig.usesThreshold == true)
        #expect(hybridConfig.usesCorrelation == true)
    }

    @Test("EchoProtectionConfiguration auto-assigns correlation config")
    func echoProtectionAutoAssignsCorrelationConfig() {
        // Correlation mode should auto-assign config
        let correlationConfig = EchoProtectionConfiguration(mode: .correlation)
        #expect(correlationConfig.correlationConfig != nil)

        // Threshold mode should not
        let thresholdConfig = EchoProtectionConfiguration(mode: .threshold)
        #expect(thresholdConfig.correlationConfig == nil)

        // Hybrid mode should auto-assign
        let hybridConfig = EchoProtectionConfiguration(mode: .hybrid)
        #expect(hybridConfig.correlationConfig != nil)
    }

    @Test("EchoProtectionConfiguration presets")
    func echoProtectionPresets() {
        #expect(EchoProtectionConfiguration.default.mode == .threshold)
        #expect(EchoProtectionConfiguration.correlationDefault.mode == .correlation)
        #expect(EchoProtectionConfiguration.hybrid.mode == .hybrid)
        #expect(EchoProtectionConfiguration.aggressive.mode == .hybrid)
        #expect(EchoProtectionConfiguration.disabled.enabled == false)
    }

    @Test("Disabled echo protection reports false for usesThreshold and usesCorrelation")
    func disabledEchoProtectionReportsFalse() {
        let disabled = EchoProtectionConfiguration.disabled

        #expect(disabled.usesThreshold == false)
        #expect(disabled.usesCorrelation == false)
    }

    // MARK: - Description Tests

    @Test("EchoCancellerConfiguration description")
    func configurationDescription() {
        let enabled = EchoCancellerConfiguration.default
        #expect(enabled.description.contains("threshold"))

        let disabled = EchoCancellerConfiguration.disabled
        #expect(disabled.description.contains("disabled"))
    }

    @Test("EchoProtectionConfiguration description")
    func protectionConfigurationDescription() {
        let threshold = EchoProtectionConfiguration(mode: .threshold)
        #expect(threshold.description.contains("threshold"))

        let correlation = EchoProtectionConfiguration(mode: .correlation)
        #expect(correlation.description.contains("correlation"))

        let hybrid = EchoProtectionConfiguration(mode: .hybrid)
        #expect(hybrid.description.contains("hybrid"))

        let disabled = EchoProtectionConfiguration.disabled
        #expect(disabled.description.contains("disabled"))
    }

    // MARK: - Equatable Tests

    @Test("EchoCancellerConfiguration equality")
    func configurationEquality() {
        let a = EchoCancellerConfiguration.default
        let b = EchoCancellerConfiguration.default
        let c = EchoCancellerConfiguration.aggressive

        #expect(a == b)
        #expect(a != c)
    }

    @Test("EchoProtectionConfiguration equality")
    func protectionConfigurationEquality() {
        let a = EchoProtectionConfiguration.hybrid
        let b = EchoProtectionConfiguration.hybrid
        let c = EchoProtectionConfiguration.default

        #expect(a == b)
        #expect(a != c)
    }
}

