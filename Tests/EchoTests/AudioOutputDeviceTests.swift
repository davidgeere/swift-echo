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

