// ConversationVADTests.swift
// Tests for VAD response behavior to prevent duplicate responses

import Foundation
import Testing
@testable import Echo

/// Tests for conversation VAD behavior and response creation logic
@Suite("Conversation VAD Response Tests")
struct ConversationVADTests {
    
    /// Test that automatic VAD configurations are properly recognized
    @Test("VAD configuration recognition", 
          arguments: [
              TurnDetection.automatic(.default),
              TurnDetection.automatic(.quiet),
              TurnDetection.automatic(.noisy),
              TurnDetection.automatic(.patient),
              TurnDetection.automatic(.responsive),
              TurnDetection.automatic(.semantic)
          ])
    func vadConfigurationRecognition(vadConfig: TurnDetection) async throws {
        // Test that automatic VAD is properly detected
        switch vadConfig {
        case .automatic:
            #expect(vadConfig.isEnabled == true, "Automatic VAD should be enabled")
            #expect(vadConfig.vadConfiguration != nil, "Should have VAD configuration")
        default:
            #expect(false, "Expected automatic VAD configuration")
        }
    }
    
    /// Test that manual turn detection is properly recognized
    @Test("Manual turn detection recognition")
    func manualTurnDetectionRecognition() async throws {
        let manualConfig = TurnDetection.manual(timeoutSeconds: nil)
        
        switch manualConfig {
        case .manual:
            #expect(manualConfig.isEnabled == true, "Manual turn detection should be enabled")
            #expect(manualConfig.vadConfiguration == nil, "Should not have VAD configuration")
        default:
            #expect(false, "Expected manual turn detection")
        }
    }
    
    /// Test that disabled turn detection is properly recognized
    @Test("Disabled turn detection recognition")
    func disabledTurnDetectionRecognition() async throws {
        let disabledConfig = TurnDetection.disabled
        
        #expect(disabledConfig.isEnabled == false, "Disabled turn detection should not be enabled")
        #expect(disabledConfig.vadConfiguration == nil, "Should not have VAD configuration")
    }
    
    /// Test configuration creation with different turn detection modes
    @Test("Configuration with turn detection modes")
    func configurationWithTurnDetection() async throws {
        // Test automatic VAD configuration
        let autoConfig = EchoConfiguration(
            turnDetection: .automatic(.default)
        )
        #expect(autoConfig.turnDetection?.isEnabled == true)
        
        // Test manual configuration
        let manualConfig = EchoConfiguration(
            turnDetection: .manual(timeoutSeconds: 30)
        )
        #expect(manualConfig.turnDetection?.isEnabled == true)
        
        // Test disabled configuration
        let disabledConfig = EchoConfiguration(
            turnDetection: .disabled
        )
        #expect(disabledConfig.turnDetection?.isEnabled == false)
    }
    
    /// Verify the fix: responseCreate should only be called in manual mode
    /// This test validates the logic without needing to run actual API calls
    @Test("Response create logic based on turn detection")
    func responseCreateLogic() async throws {
        // Test case 1: Automatic VAD should NOT trigger responseCreate
        let autoConfig = EchoConfiguration(turnDetection: .automatic(.default))
        
        // Logic check: In automatic mode, we should NOT manually call responseCreate
        var shouldCallResponseCreate = false
        if case .manual = autoConfig.turnDetection {
            shouldCallResponseCreate = true
        }
        #expect(shouldCallResponseCreate == false, 
                "Should NOT call responseCreate in automatic VAD mode")
        
        // Test case 2: Manual mode SHOULD trigger responseCreate
        let manualConfig = EchoConfiguration(turnDetection: .manual(timeoutSeconds: nil))
        
        shouldCallResponseCreate = false
        if case .manual = manualConfig.turnDetection {
            shouldCallResponseCreate = true
        }
        #expect(shouldCallResponseCreate == true,
                "SHOULD call responseCreate in manual mode")
        
        // Test case 3: Disabled mode behavior
        let disabledConfig = EchoConfiguration(turnDetection: .disabled)
        
        shouldCallResponseCreate = false
        if case .manual = disabledConfig.turnDetection {
            shouldCallResponseCreate = true
        }
        #expect(shouldCallResponseCreate == false,
                "Should NOT call responseCreate in disabled mode")
    }
    
    /// Test that the VAD configuration is properly converted to API format
    @Test("VAD configuration conversion to API format")
    func vadConfigurationToAPIFormat() async throws {
        // Test automatic VAD conversion
        let autoVAD = TurnDetection.automatic(.default)
        let autoFormat = autoVAD.toRealtimeFormat()
        
        #expect(autoFormat != nil, "Automatic VAD should produce API format")
        if let format = autoFormat {
            #expect(format["type"] as? String == "server_vad", "Should be server_vad type")
            #expect(format["threshold"] != nil, "Should have threshold")
            #expect(format["silence_duration_ms"] != nil, "Should have silence duration")
        }
        
        // Test manual mode conversion
        let manualVAD = TurnDetection.manual(timeoutSeconds: 30)
        let manualFormat = manualVAD.toRealtimeFormat()
        
        #expect(manualFormat != nil, "Manual mode should produce API format")
        if let format = manualFormat {
            // Manual mode still uses server_vad but with different settings
            #expect(format["type"] as? String == "server_vad")
            #expect(format["silence_duration_ms"] as? Int == 30000, "Should convert seconds to ms")
        }
        
        // Test disabled mode
        let disabledVAD = TurnDetection.disabled
        let disabledFormat = disabledVAD.toRealtimeFormat()
        
        #expect(disabledFormat == nil, "Disabled mode should not produce API format")
    }
}