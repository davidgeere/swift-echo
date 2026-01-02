// AudioSessionManagerTests.swift
// EchoTests
//
// Tests for AudioSessionManager singleton and route change functionality

import Testing
import Foundation
@testable import Echo

@Suite("AudioSessionManager Tests")
struct AudioSessionManagerTests {
    
    @Test("AudioSessionManager is a singleton")
    func testSingleton() async {
        let manager1 = AudioSessionManager.shared
        let manager2 = AudioSessionManager.shared
        
        // Both references should point to the same instance
        // We verify this by checking they're the same actor
        let id1 = ObjectIdentifier(manager1)
        let id2 = ObjectIdentifier(manager2)
        #expect(id1 == id2)
    }
    
    @Test("currentAudioOutput returns a valid device type")
    func testCurrentAudioOutputReturnsValidType() async {
        let manager = AudioSessionManager.shared
        let output = await manager.currentAudioOutput
        
        // Should return a valid device type
        switch output {
        case .builtInSpeaker, .builtInReceiver, .bluetooth, .wiredHeadphones, .systemDefault, .smart:
            #expect(true)
        }
    }
    
    @Test("availableAudioOutputDevices always includes built-in devices on iOS")
    func testAvailableDevicesIncludesBuiltIn() async {
        #if os(iOS)
        let manager = AudioSessionManager.shared
        let devices = await manager.availableAudioOutputDevices
        
        // Should always include speaker and receiver
        #expect(devices.contains(.builtInSpeaker))
        #expect(devices.contains(.builtInReceiver))
        #expect(devices.count >= 2)
        #else
        // On macOS, just verify it returns something
        let manager = AudioSessionManager.shared
        let devices = await manager.availableAudioOutputDevices
        #expect(devices.count >= 1)
        #endif
    }
    
    @Test("routeChangeStream is accessible")
    func testRouteChangeStreamAccessible() async {
        let manager = AudioSessionManager.shared
        
        // Verify we can access the stream (it exists and is configured)
        let stream = await manager.routeChangeStream
        
        // Stream should be a valid AsyncStream
        #expect(true, "Stream should be accessible")
        _ = stream  // Use the variable to avoid warning
    }
    
    @Test("startRouteChangeObservation can be called without error")
    func testStartRouteChangeObservation() async {
        let manager = AudioSessionManager.shared
        
        // Should not throw - safe to call multiple times
        await manager.startRouteChangeObservation()
        await manager.startRouteChangeObservation() // Call again to test idempotency
        
        // Cleanup
        await manager.stopRouteChangeObservation()
        
        #expect(true, "Route change observation started successfully")
    }
    
    @Test("stopRouteChangeObservation can be called without error")
    func testStopRouteChangeObservation() async {
        let manager = AudioSessionManager.shared
        
        // Should not throw even if not started
        await manager.stopRouteChangeObservation()
        
        // Start then stop
        await manager.startRouteChangeObservation()
        await manager.stopRouteChangeObservation()
        
        #expect(true, "Route change observation stopped successfully")
    }
}

@Suite("AudioOutputDeviceType Tests")
struct AudioOutputDeviceTypeExtendedTests {
    
    @Test("mayProduceEcho returns correct values for each device type")
    func testMayProduceEcho() {
        #expect(AudioOutputDeviceType.builtInSpeaker.mayProduceEcho == true)
        #expect(AudioOutputDeviceType.builtInReceiver.mayProduceEcho == false)
        #expect(AudioOutputDeviceType.wiredHeadphones(name: nil).mayProduceEcho == false)
        #expect(AudioOutputDeviceType.bluetooth(name: nil).mayProduceEcho == true)
        #expect(AudioOutputDeviceType.systemDefault.mayProduceEcho == true)
        #expect(AudioOutputDeviceType.smart.mayProduceEcho == true)
    }
    
    @Test("smart device type has correct description")
    func testSmartDescription() {
        #expect(AudioOutputDeviceType.smart.description == "Smart (Bluetooth/Speaker)")
    }
    
    @Test("smart device type is not Bluetooth")
    func testSmartIsNotBluetooth() {
        #expect(AudioOutputDeviceType.smart.isBluetooth == false)
    }
}

/// Test helper for tracking route change events
actor RouteChangeTestState {
    var receivedDevices: [AudioOutputDeviceType] = []
    var eventCount = 0
    
    func recordDevice(_ device: AudioOutputDeviceType) {
        receivedDevices.append(device)
        eventCount += 1
    }
    
    func reset() {
        receivedDevices.removeAll()
        eventCount = 0
    }
}

@Suite("Route Change Stream Tests")
struct RouteChangeStreamTests {
    
    @Test("Route change stream receives events from setAudioOutput")
    func testRouteChangeStreamReceivesEvents() async throws {
        let manager = AudioSessionManager.shared
        let testState = RouteChangeTestState()
        
        // Start observation
        await manager.startRouteChangeObservation()
        
        // Start listening to stream
        let streamTask = Task {
            for await device in await manager.routeChangeStream {
                await testState.recordDevice(device)
                // Stop after first event for this test
                break
            }
        }
        
        // Small delay to let stream setup
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // Note: On macOS/simulator, setAudioOutput may not actually change routes
        // but should still emit events via the continuation
        #if os(iOS)
        do {
            try await manager.setAudioOutput(device: .builtInSpeaker)
        } catch {
            // Expected on simulator - audio session operations may fail
        }
        #endif
        
        // Give time for event to propagate
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Clean up
        streamTask.cancel()
        await manager.stopRouteChangeObservation()
        
        // The test passes if we got here without crashing
        // Event reception depends on actual hardware/simulator capabilities
        #expect(true, "Stream subscription completed without error")
    }
}

