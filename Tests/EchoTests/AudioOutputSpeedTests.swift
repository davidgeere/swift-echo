// AudioOutputSpeedTests.swift
// EchoTests
//
// Tests for audio output speed parameter functionality

import Testing
import Foundation
@testable import Echo

@Suite("Audio Output Speed")
struct AudioOutputSpeedTests {

    // MARK: - EchoConfiguration Speed Tests

    @Test("EchoConfiguration has default speed of 1.0")
    func testEchoConfigurationDefaultSpeed() {
        let config = EchoConfiguration()
        
        #expect(config.speed == 1.0, "Default speed should be 1.0")
    }
    
    @Test("EchoConfiguration accepts custom speed value")
    func testEchoConfigurationCustomSpeed() {
        let config = EchoConfiguration(speed: 1.5)
        
        #expect(config.speed == 1.5, "Speed should be configurable")
    }
    
    @Test("EchoConfiguration speed is converted to RealtimeClientConfiguration")
    func testSpeedPassedToRealtimeClientConfiguration() {
        let echoConfig = EchoConfiguration(speed: 1.2)
        let realtimeConfig = echoConfig.toRealtimeClientConfiguration()
        
        #expect(realtimeConfig.speed == 1.2, "Speed should be passed through")
    }
    
    // MARK: - RealtimeClientConfiguration Speed Tests
    
    @Test("RealtimeClientConfiguration has default speed of 1.0")
    func testRealtimeClientConfigurationDefaultSpeed() {
        let config = RealtimeClientConfiguration(
            model: .gptRealtime
        )
        
        #expect(config.speed == 1.0, "Default speed should be 1.0")
    }
    
    @Test("RealtimeClientConfiguration accepts custom speed value")
    func testRealtimeClientConfigurationCustomSpeed() {
        let config = RealtimeClientConfiguration(
            model: .gptRealtime,
            speed: 0.75
        )
        
        #expect(config.speed == 0.75, "Speed should be configurable")
    }
    
    // MARK: - RealtimeSession Speed Tests
    
    @Test("RealtimeSession has default speed of 1.0")
    func testRealtimeSessionDefaultSpeed() {
        let session = RealtimeSession(
            model: .gptRealtime
        )
        
        #expect(session.speed == 1.0, "Default speed should be 1.0")
    }
    
    @Test("RealtimeSession accepts custom speed value")
    func testRealtimeSessionCustomSpeed() {
        let session = RealtimeSession(
            model: .gptRealtime,
            speed: 1.25
        )
        
        #expect(session.speed == 1.25, "Speed should be configurable")
    }
    
    @Test("RealtimeSession toRealtimeFormat includes speed")
    func testRealtimeSessionToRealtimeFormatIncludesSpeed() {
        let session = RealtimeSession(
            model: .gptRealtime,
            speed: 1.25
        )
        
        let format = session.toRealtimeFormat()
        
        // Speed should be included using the string key format like temperature
        if let speedString = format["__speed_string"] as? String {
            #expect(speedString == "1.25", "Speed should be formatted to 2 decimal places")
        } else {
            Issue.record("Speed should be included in toRealtimeFormat output")
        }
    }
    
    @Test("RealtimeSession toRealtimeFormat excludes nil speed")
    func testRealtimeSessionToRealtimeFormatExcludesNilSpeed() {
        let session = RealtimeSession(
            model: .gptRealtime,
            speed: nil
        )
        
        let format = session.toRealtimeFormat()
        
        #expect(format["__speed_string"] == nil, "Nil speed should not be included")
    }
    
    // MARK: - Speed Range Tests
    
    @Test("Speed values at boundary limits are accepted")
    func testSpeedBoundaryValues() {
        // Test minimum expected value (0.25)
        let minConfig = EchoConfiguration(speed: 0.25)
        #expect(minConfig.speed == 0.25)
        
        // Test maximum expected value (4.0)
        let maxConfig = EchoConfiguration(speed: 4.0)
        #expect(maxConfig.speed == 4.0)
        
        // Test normal speed
        let normalConfig = EchoConfiguration(speed: 1.0)
        #expect(normalConfig.speed == 1.0)
    }
    
    // MARK: - Integration Tests
    
    @Test("Speed flows through entire configuration chain")
    func testSpeedFlowsThroughConfigurationChain() {
        // Create EchoConfiguration with custom speed
        let echoConfig = EchoConfiguration(
            defaultMode: .audio,
            speed: 1.5
        )
        
        // Convert to RealtimeClientConfiguration
        let realtimeClientConfig = echoConfig.toRealtimeClientConfiguration()
        
        // Verify speed is preserved
        #expect(realtimeClientConfig.speed == 1.5)
    }
    
    // MARK: - Example Usage Tests
    
    @Test("Example usage from issue #20")
    func testExampleUsageFromIssue() {
        let config = EchoConfiguration(
            defaultMode: .audio,
            voice: .ash,
            speed: 1.2  // 20% faster than normal
        )
        
        #expect(config.speed == 1.2)
        #expect(config.voice == .ash)
        #expect(config.defaultMode == .audio)
    }
}

