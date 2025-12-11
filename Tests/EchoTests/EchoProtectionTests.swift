// EchoProtectionTests.swift
// Echo Tests
// Tests for echo protection functionality

import Foundation
import Testing

@testable import Echo

@Suite
struct EchoProtectionTests {
    // MARK: - VADConfiguration Tests

    @Test
    func vadConfigurationHasEagernessProperty() {
        let config = VADConfiguration(type: .semanticVAD, eagerness: .low)
        #expect(config.eagerness == .low)
    }

    @Test
    func vadConfigurationHasCreateResponseProperty() {
        let config = VADConfiguration(createResponse: false)
        #expect(config.createResponse == false)
    }

    @Test
    func vadConfigurationHasInterruptResponseProperty() {
        let config = VADConfiguration(interruptResponse: false)
        #expect(config.interruptResponse == false)
    }

    @Test
    func vadConfigurationServerVADSerialization() {
        let config = VADConfiguration(
            type: .serverVAD,
            threshold: 0.7,
            silenceDurationMs: 600,
            prefixPaddingMs: 400,
            interruptResponse: true,
            createResponse: true
        )

        let format = config.toRealtimeFormat()

        #expect(format["type"] as? String == "server_vad")
        #expect(format["threshold"] as? Double == 0.7)
        #expect(format["silence_duration_ms"] as? Int == 600)
        #expect(format["prefix_padding_ms"] as? Int == 400)
        #expect(format["create_response"] as? Bool == true)
        #expect(format["interrupt_response"] as? Bool == true)
        // Server VAD should not include eagerness
        #expect(format["eagerness"] == nil)
    }

    @Test
    func vadConfigurationSemanticVADSerialization() {
        let config = VADConfiguration(
            type: .semanticVAD,
            eagerness: .low,
            interruptResponse: true,
            createResponse: true
        )

        let format = config.toRealtimeFormat()

        #expect(format["type"] as? String == "semantic_vad")
        #expect(format["eagerness"] as? String == "low")
        #expect(format["create_response"] as? Bool == true)
        #expect(format["interrupt_response"] as? Bool == true)
        // Semantic VAD should not include threshold/silence/prefix
        #expect(format["threshold"] == nil)
        #expect(format["silence_duration_ms"] == nil)
        #expect(format["prefix_padding_ms"] == nil)
    }

    @Test
    func vadConfigurationSpeakerOptimizedPreset() {
        let config = VADConfiguration.speakerOptimized

        #expect(config.type == .semanticVAD)
        #expect(config.eagerness == .low)
        #expect(config.interruptResponse == true)
        #expect(config.createResponse == true)
    }

    @Test
    func vadConfigurationEarpiecePreset() {
        let config = VADConfiguration.earpiece

        #expect(config.type == .serverVAD)
        #expect(config.eagerness == .high)
    }

    @Test
    func vadConfigurationBluetoothPreset() {
        let config = VADConfiguration.bluetooth

        #expect(config.type == .semanticVAD)
        #expect(config.eagerness == .medium)
    }

    // MARK: - InputAudioConfiguration Tests

    @Test
    func inputAudioConfigurationNearFieldPreset() {
        let config = InputAudioConfiguration.nearField
        #expect(config.noiseReductionType == .nearField)
    }

    @Test
    func inputAudioConfigurationFarFieldPreset() {
        let config = InputAudioConfiguration.farField
        #expect(config.noiseReductionType == .farField)
    }

    @Test
    func inputAudioConfigurationDisabledPreset() {
        let config = InputAudioConfiguration.disabled
        #expect(config.noiseReductionType == nil)
    }

    @Test
    func inputAudioConfigurationSerialization() {
        let config = InputAudioConfiguration(noiseReductionType: .farField)
        let format = config.toRealtimeFormat()

        #expect(format != nil)

        if let format = format {
            let noiseReduction = format["noise_reduction"] as? [String: Any]
            #expect(noiseReduction != nil)
            #expect(noiseReduction?["type"] as? String == "far_field")
        }
    }

    @Test
    func inputAudioConfigurationDisabledReturnsNil() {
        let config = InputAudioConfiguration.disabled
        let format = config.toRealtimeFormat()

        #expect(format == nil)
    }

    // MARK: - EchoProtectionConfiguration Tests

    @Test
    func echoProtectionConfigurationDefaultPreset() {
        let config = EchoProtectionConfiguration.default

        #expect(config.enabled == true)
        #expect(config.bargeInThreshold == 0.15)
        #expect(config.postSpeechDelay == .milliseconds(300))
    }

    @Test
    func echoProtectionConfigurationAggressivePreset() {
        let config = EchoProtectionConfiguration.aggressive

        #expect(config.enabled == true)
        #expect(config.bargeInThreshold == 0.25)
        #expect(config.postSpeechDelay == .milliseconds(500))
    }

    @Test
    func echoProtectionConfigurationDisabledPreset() {
        let config = EchoProtectionConfiguration.disabled

        #expect(config.enabled == false)
        #expect(config.bargeInThreshold == 0.0)
    }

    @Test
    func echoProtectionConfigurationThresholdClamping() {
        // Test that threshold is clamped to 0.0-1.0
        let configHigh = EchoProtectionConfiguration(bargeInThreshold: 1.5)
        #expect(configHigh.bargeInThreshold == 1.0)

        let configLow = EchoProtectionConfiguration(bargeInThreshold: -0.5)
        #expect(configLow.bargeInThreshold == 0.0)
    }

    // MARK: - AudioOutputDeviceType Tests

    @Test
    func audioOutputDeviceTypeSmartCase() {
        let device = AudioOutputDeviceType.smart
        #expect(device.description == "Smart (Bluetooth/Speaker)")
    }

    @Test
    func audioOutputDeviceTypeMayProduceEchoSpeaker() {
        #expect(AudioOutputDeviceType.builtInSpeaker.mayProduceEcho == true)
    }

    @Test
    func audioOutputDeviceTypeMayProduceEchoReceiver() {
        #expect(AudioOutputDeviceType.builtInReceiver.mayProduceEcho == false)
    }

    @Test
    func audioOutputDeviceTypeMayProduceEchoHeadphones() {
        #expect(AudioOutputDeviceType.wiredHeadphones(name: nil).mayProduceEcho == false)
    }

    @Test
    func audioOutputDeviceTypeMayProduceEchoBluetooth() {
        // Bluetooth may produce echo (speakers vs earbuds unknown)
        #expect(AudioOutputDeviceType.bluetooth(name: nil).mayProduceEcho == true)
    }

    @Test
    func audioOutputDeviceTypeMayProduceEchoSmart() {
        // Smart mode may use speaker, so conservatively assume echo
        #expect(AudioOutputDeviceType.smart.mayProduceEcho == true)
    }

    // MARK: - EchoConfiguration Tests

    @Test
    func echoConfigurationHasDefaultAudioOutput() {
        let config = EchoConfiguration(defaultAudioOutput: .smart)
        #expect(config.defaultAudioOutput == .smart)
    }

    @Test
    func echoConfigurationHasInputAudioConfiguration() {
        let config = EchoConfiguration(inputAudioConfiguration: .farField)
        #expect(config.inputAudioConfiguration?.noiseReductionType == .farField)
    }

    @Test
    func echoConfigurationHasEchoProtection() {
        let config = EchoConfiguration(echoProtection: .aggressive)
        #expect(config.echoProtection?.bargeInThreshold == 0.25)
    }

    @Test
    func echoConfigurationSpeakerOptimizedPreset() {
        let config = EchoConfiguration.speakerOptimized

        #expect(config.defaultMode == .audio)
        #expect(config.defaultAudioOutput == .smart)
        #expect(config.inputAudioConfiguration?.noiseReductionType == .farField)
        #expect(config.echoProtection?.enabled == true)
    }

    @Test
    func echoConfigurationConversionIncludesNewFields() {
        let config = EchoConfiguration(
            defaultAudioOutput: .smart,
            inputAudioConfiguration: .farField,
            echoProtection: .default
        )

        let realtimeConfig = config.toRealtimeClientConfiguration()

        #expect(realtimeConfig.defaultAudioOutput == .smart)
        #expect(realtimeConfig.inputAudioConfiguration?.noiseReductionType == .farField)
        #expect(realtimeConfig.echoProtection?.enabled == true)
    }

    // MARK: - RealtimeClientConfiguration Tests

    @Test
    func realtimeClientConfigurationSpeakerOptimizedPreset() {
        let config = RealtimeClientConfiguration.speakerOptimized

        #expect(config.defaultAudioOutput == .smart)
        #expect(config.echoProtection != nil)
        #expect(config.inputAudioConfiguration?.noiseReductionType == .farField)
    }

    // MARK: - AudioCapture Gating Tests

    @Test
    func audioCaptureSupportGating() async {
        let capture = MockAudioCapture()

        // Initially gating should be disabled
        let initialGating = await capture.isGatingEnabled
        #expect(initialGating == false)

        // Enable gating
        await capture.enableGating(threshold: 0.15)
        let enabledGating = await capture.isGatingEnabled
        #expect(enabledGating == true)

        // Disable gating
        await capture.disableGating()
        let disabledGating = await capture.isGatingEnabled
        #expect(disabledGating == false)
    }

    @Test
    func audioCaptureGatingResetsOnStop() async throws {
        let capture = MockAudioCapture()

        // Enable gating
        await capture.enableGating(threshold: 0.15)
        #expect(await capture.isGatingEnabled == true)

        // Stop should reset gating
        await capture.stop()
        #expect(await capture.isGatingEnabled == false)
    }
}

