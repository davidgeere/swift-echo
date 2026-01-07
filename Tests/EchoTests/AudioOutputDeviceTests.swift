// AudioOutputDeviceTests.swift
// EchoTests
//
// Tests for audio output device selection functionality

import Testing
import Foundation
@testable import Echo

@Suite("Audio Output Device Tests")
struct AudioOutputDeviceTests {
    
    @Test("AudioOutputDeviceType description returns correct strings")
    func testDeviceTypeDescriptions() {
        #expect(AudioOutputDeviceType.builtInSpeaker.description == "Speaker")
        #expect(AudioOutputDeviceType.builtInReceiver.description == "Earpiece")
        #expect(AudioOutputDeviceType.bluetooth(name: "AirPods Pro").description == "AirPods Pro")
        #expect(AudioOutputDeviceType.bluetooth(name: nil).description == "Bluetooth")
        #expect(AudioOutputDeviceType.wiredHeadphones(name: "Beats").description == "Beats")
        #expect(AudioOutputDeviceType.wiredHeadphones(name: nil).description == "Headphones")
        #expect(AudioOutputDeviceType.systemDefault.description == "System Default")
    }
    
    @Test("AudioOutputDeviceType isBluetooth property works correctly")
    func testIsBluetoothProperty() {
        #expect(AudioOutputDeviceType.builtInSpeaker.isBluetooth == false)
        #expect(AudioOutputDeviceType.builtInReceiver.isBluetooth == false)
        #expect(AudioOutputDeviceType.bluetooth(name: "AirPods").isBluetooth == true)
        #expect(AudioOutputDeviceType.wiredHeadphones(name: nil).isBluetooth == false)
        #expect(AudioOutputDeviceType.systemDefault.isBluetooth == false)
        #expect(AudioOutputDeviceType.smart.isBluetooth == false)
    }
    
    @Test("AudioOutputDeviceType isWiredHeadphones property works correctly")
    func testIsWiredHeadphonesProperty() {
        #expect(AudioOutputDeviceType.builtInSpeaker.isWiredHeadphones == false)
        #expect(AudioOutputDeviceType.builtInReceiver.isWiredHeadphones == false)
        #expect(AudioOutputDeviceType.bluetooth(name: "AirPods").isWiredHeadphones == false)
        #expect(AudioOutputDeviceType.wiredHeadphones(name: "Beats").isWiredHeadphones == true)
        #expect(AudioOutputDeviceType.wiredHeadphones(name: nil).isWiredHeadphones == true)
        #expect(AudioOutputDeviceType.systemDefault.isWiredHeadphones == false)
        #expect(AudioOutputDeviceType.smart.isWiredHeadphones == false)
    }
    
    @Test("AudioOutputDeviceType isExternalAudioDevice property works correctly")
    func testIsExternalAudioDeviceProperty() {
        // Built-in devices are NOT external
        #expect(AudioOutputDeviceType.builtInSpeaker.isExternalAudioDevice == false)
        #expect(AudioOutputDeviceType.builtInReceiver.isExternalAudioDevice == false)
        #expect(AudioOutputDeviceType.systemDefault.isExternalAudioDevice == false)
        #expect(AudioOutputDeviceType.smart.isExternalAudioDevice == false)
        
        // Bluetooth IS external
        #expect(AudioOutputDeviceType.bluetooth(name: "AirPods").isExternalAudioDevice == true)
        #expect(AudioOutputDeviceType.bluetooth(name: nil).isExternalAudioDevice == true)
        
        // Wired headphones ARE external
        #expect(AudioOutputDeviceType.wiredHeadphones(name: "Beats").isExternalAudioDevice == true)
        #expect(AudioOutputDeviceType.wiredHeadphones(name: nil).isExternalAudioDevice == true)
    }
    
    @Test("AudioOutputDeviceType equality works correctly")
    func testDeviceTypeEquality() {
        #expect(AudioOutputDeviceType.builtInSpeaker == .builtInSpeaker)
        #expect(AudioOutputDeviceType.bluetooth(name: "AirPods") == .bluetooth(name: "AirPods"))
        #expect(AudioOutputDeviceType.bluetooth(name: "AirPods") != .bluetooth(name: "Beats"))
        #expect(AudioOutputDeviceType.builtInSpeaker != .builtInReceiver)
    }
    
    @Test("MockAudioPlayback returns available devices")
    func testMockAvailableDevices() async {
        let mock = MockAudioPlayback()
        let devices = await mock.availableAudioOutputDevices
        
        #expect(devices.count >= 3)
        #expect(devices.contains(.builtInSpeaker))
        #expect(devices.contains(.builtInReceiver))
        #expect(devices.contains { 
            if case .bluetooth(let name) = $0 {
                return name == "Mock AirPods"
            }
            return false
        })
    }
    
    @Test("MockAudioPlayback currentAudioOutput defaults to systemDefault")
    func testMockCurrentOutputDefault() async {
        let mock = MockAudioPlayback()
        let current = await mock.currentAudioOutput
        
        #expect(current == .systemDefault)
    }
    
    @Test("MockAudioPlayback setAudioOutput updates current output")
    func testMockSetAudioOutput() async throws {
        let mock = MockAudioPlayback()
        try await mock.start()
        
        try await mock.setAudioOutput(device: .builtInSpeaker)
        let current = await mock.currentAudioOutput
        #expect(current == .builtInSpeaker)
        
        try await mock.setAudioOutput(device: .bluetooth(name: "Test"))
        let current2 = await mock.currentAudioOutput
        #expect(current2 == .bluetooth(name: "Test"))
    }
    
    @Test("MockAudioPlayback setAudioOutput throws when not started")
    func testMockSetAudioOutputThrowsWhenNotStarted() async {
        let mock = MockAudioPlayback()
        
        await #expect(throws: RealtimeError.self) {
            try await mock.setAudioOutput(device: .builtInSpeaker)
        }
    }
}

/// Test state for tracking audio output change events
actor AudioOutputTestState {
    var receivedDevice: AudioOutputDeviceType?
    var eventReceived = false
    
    func recordEvent(_ device: AudioOutputDeviceType) {
        receivedDevice = device
        eventReceived = true
    }
    
    func reset() {
        receivedDevice = nil
        eventReceived = false
    }
}

@Suite("Audio Output Device Event Tests")
struct AudioOutputDeviceEventTests {
    
    @Test("audioOutputChanged event is emitted when setAudioOutput is called")
    func testAudioOutputChangedEvent() async throws {
        let emitter = EventEmitter()
        let state = AudioOutputTestState()
        
        // Start consuming events from stream
        let eventTask = Task {
            for await event in emitter.events {
                if case .audioOutputChanged(let device) = event {
                    await state.recordEvent(device)
                    break
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Create RealtimeClient with mock playback
        let config = RealtimeClientConfiguration(
            model: .gptRealtimeMini,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            enableTranscription: false,
            startAudioAutomatically: false
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        // Start audio
        try await client.startAudio()
        
        // Set audio output
        try await client.setAudioOutput(device: .builtInSpeaker)
        
        // Small delay to let event propagate
        try await Task.sleep(nanoseconds: 50_000_000)
        
        eventTask.cancel()
        
        // Verify event was received
        let eventReceived = await state.eventReceived
        let receivedDevice = await state.receivedDevice
        #expect(eventReceived == true)
        #expect(receivedDevice != nil)
    }
    
    @Test("RealtimeClient availableAudioOutputDevices delegates to playback")
    func testRealtimeClientAvailableDevices() async throws {
        let emitter = EventEmitter()
        let config = RealtimeClientConfiguration(
            model: .gptRealtimeMini,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            enableTranscription: false,
            startAudioAutomatically: false
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        try await client.startAudio()
        
        let devices = await client.availableAudioOutputDevices
        #expect(devices.count >= 3)
        #expect(devices.contains(.builtInSpeaker))
    }
    
    @Test("RealtimeClient currentAudioOutput delegates to playback")
    func testRealtimeClientCurrentOutput() async throws {
        let emitter = EventEmitter()
        let config = RealtimeClientConfiguration(
            model: .gptRealtimeMini,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            enableTranscription: false,
            startAudioAutomatically: false
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioPlaybackFactory: { MockAudioPlayback() }
        )
        
        try await client.startAudio()
        
        let current = await client.currentAudioOutput
        #expect(current == .systemDefault)
        
        try await client.setAudioOutput(device: .builtInSpeaker)
        let current2 = await client.currentAudioOutput
        #expect(current2 == .builtInSpeaker)
    }
    
    @Test("Conversation setAudioOutput throws in text mode")
    func testConversationSetAudioOutputThrowsInTextMode() async throws {
        let echo = Echo(key: "test-key")
        let conversation = try await echo.startConversation(mode: .text)
        
        await #expect(throws: EchoError.self) {
            try await conversation.setAudioOutput(device: .builtInSpeaker)
        }
    }
    
    @Test("Conversation availableAudioOutputDevices returns empty in text mode")
    func testConversationAvailableDevicesInTextMode() async throws {
        let echo = Echo(key: "test-key")
        let conversation = try await echo.startConversation(mode: .text)
        
        let devices = await conversation.availableAudioOutputDevices
        #expect(devices.isEmpty)
    }
    
    @Test("Conversation currentAudioOutput returns systemDefault in text mode")
    func testConversationCurrentOutputInTextMode() async throws {
        let echo = Echo(key: "test-key")
        let conversation = try await echo.startConversation(mode: .text)
        
        let current = await conversation.currentAudioOutput
        #expect(current == .systemDefault)
    }
}

@Suite("Smart Audio Output Selection Tests (SAM-129)")
struct SmartAudioOutputSelectionTests {
    
    @Test("Smart mode selects Bluetooth when available")
    func testSmartSelectsBluetooth() async throws {
        // Arrange: Mock with Bluetooth device available
        let mockPlayback = MockAudioPlayback(availableDevices: [
            .builtInSpeaker,
            .builtInReceiver,
            .bluetooth(name: "AirPods Pro")
        ])
        
        let emitter = EventEmitter()
        let config = RealtimeClientConfiguration(
            model: .gptRealtimeMini,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            enableTranscription: false,
            startAudioAutomatically: false,
            defaultAudioOutput: .smart
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioPlaybackFactory: { mockPlayback }
        )
        
        // Act: Start audio (which applies default audio output)
        try await client.startAudio()
        
        // Assert: Should select Bluetooth
        let currentOutput = await client.currentAudioOutput
        #expect(currentOutput.isBluetooth == true)
    }
    
    @Test("Smart mode selects wired headphones when no Bluetooth available")
    func testSmartSelectsWiredHeadphones() async throws {
        // Arrange: Mock with only wired headphones (no Bluetooth)
        let mockPlayback = MockAudioPlayback(availableDevices: [
            .builtInSpeaker,
            .builtInReceiver,
            .wiredHeadphones(name: "EarPods")
        ])
        
        let emitter = EventEmitter()
        let config = RealtimeClientConfiguration(
            model: .gptRealtimeMini,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            enableTranscription: false,
            startAudioAutomatically: false,
            defaultAudioOutput: .smart
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioPlaybackFactory: { mockPlayback }
        )
        
        // Act: Start audio (which applies default audio output)
        try await client.startAudio()
        
        // Assert: Should select wired headphones
        let currentOutput = await client.currentAudioOutput
        #expect(currentOutput.isWiredHeadphones == true)
    }
    
    @Test("Smart mode prioritizes Bluetooth over wired headphones")
    func testSmartPrioritizesBluetooth() async throws {
        // Arrange: Mock with BOTH Bluetooth AND wired headphones
        let mockPlayback = MockAudioPlayback(availableDevices: [
            .builtInSpeaker,
            .builtInReceiver,
            .wiredHeadphones(name: "EarPods"),
            .bluetooth(name: "AirPods Pro")
        ])
        
        let emitter = EventEmitter()
        let config = RealtimeClientConfiguration(
            model: .gptRealtimeMini,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            enableTranscription: false,
            startAudioAutomatically: false,
            defaultAudioOutput: .smart
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioPlaybackFactory: { mockPlayback }
        )
        
        // Act: Start audio (which applies default audio output)
        try await client.startAudio()
        
        // Assert: Should select Bluetooth (higher priority)
        let currentOutput = await client.currentAudioOutput
        #expect(currentOutput.isBluetooth == true)
    }
    
    @Test("Smart mode falls back to speaker when no external devices available")
    func testSmartFallsBackToSpeaker() async throws {
        // Arrange: Mock with NO external devices (no Bluetooth, no wired)
        let mockPlayback = MockAudioPlayback(availableDevices: [
            .builtInSpeaker,
            .builtInReceiver
        ])
        
        let emitter = EventEmitter()
        let config = RealtimeClientConfiguration(
            model: .gptRealtimeMini,
            voice: .alloy,
            audioFormat: .pcm16,
            turnDetection: .disabled,
            enableTranscription: false,
            startAudioAutomatically: false,
            defaultAudioOutput: .smart
        )
        
        let client = RealtimeClient(
            apiKey: "test-key",
            configuration: config,
            eventEmitter: emitter,
            audioPlaybackFactory: { mockPlayback }
        )
        
        // Act: Start audio (which applies default audio output)
        try await client.startAudio()
        
        // Assert: Should fall back to speaker
        let currentOutput = await client.currentAudioOutput
        #expect(currentOutput == .builtInSpeaker)
    }
}

