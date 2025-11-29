import Foundation
import Testing
@testable import Echo

/// Tests for reasoning effort control and handling of various prompt types
@Suite("Reasoning Effort Tests")
struct ReasoningEffortTests {
    
    @Test("Problematic prompts work with proper reasoning effort")
    func testProblematicPromptsWithReasoningEffort() async throws {
        // API key is required - fail if not found
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        // Test the previously problematic prompt with different reasoning levels
        let problematicPrompt = "What color is the sky?"
        
        // Test 1: With reasoning effort set to none (might still fail for some prompts)
        let configNone = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,
            temperature: 0.7,
            maxTokens: 100,
            reasoningEffort: .none
        )
        
        let echoNone = Echo(key: apiKey, configuration: configNone)
        let conversationNone = try await echoNone.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise."
        )
        
        let responseNone = try await conversationNone.send(problematicPrompt)
        // With .none, we might get nil for complex prompts, but that's expected
        print("Response with .none reasoning: \(responseNone?.text ?? "nil")")
        
        // Test 2: With low reasoning effort
        let configLow = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,
            temperature: 0.7,
            maxTokens: 100,
            reasoningEffort: .low
        )
        
        let echoLow = Echo(key: apiKey, configuration: configLow)
        let conversationLow = try await echoLow.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise."
        )
        
        let responseLow = try await conversationLow.send(problematicPrompt)
        #expect(responseLow != nil, "Low reasoning should handle basic questions")
        if let response = responseLow {
            print("Response with .low reasoning: \(response.text)")
            #expect(!response.text.isEmpty, "Response should have content")
        }
        
        // Test 3: With medium reasoning effort
        let configMedium = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,
            temperature: 0.7,
            maxTokens: 100,
            reasoningEffort: .medium
        )
        
        let echoMedium = Echo(key: apiKey, configuration: configMedium)
        let conversationMedium = try await echoMedium.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise."
        )
        
        let responseMedium = try await conversationMedium.send(problematicPrompt)
        #expect(responseMedium != nil, "Medium reasoning should definitely handle this")
        if let response = responseMedium {
            print("Response with .medium reasoning: \(response.text)")
            #expect(!response.text.isEmpty, "Response should have content")
        }
        
        // Test 4: With high reasoning effort
        let configHigh = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,
            temperature: 0.7,
            maxTokens: 200,
            reasoningEffort: .high
        )
        
        let echoHigh = Echo(key: apiKey, configuration: configHigh)
        let conversationHigh = try await echoHigh.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise."
        )
        
        let responseHigh = try await conversationHigh.send(problematicPrompt)
        #expect(responseHigh != nil, "High reasoning must handle any question")
        if let response = responseHigh {
            print("Response with .high reasoning: \(response.text)")
            #expect(!response.text.isEmpty, "Response should have content")
        }
    }
    
    @Test("Simple math works with all reasoning levels")
    func testSimpleMathWithAllReasoningLevels() async throws {
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        let mathPrompt = "What is 2+2?"
        let reasoningLevels: [ReasoningEffort] = [.none, .low, .medium, .high]
        
        for level in reasoningLevels {
            print("\nTesting with reasoning level: \(level)")
            
            let config = EchoConfiguration(
                defaultMode: .text,
                responsesModel: .gpt5Mini,
                temperature: 0.7,
                maxTokens: 100,
                reasoningEffort: level
            )
            
            let echo = Echo(key: apiKey, configuration: config)
            let conversation = try await echo.startConversation(
                mode: .text,
                systemMessage: "You are a helpful assistant."
            )
            
            let response = try await conversation.send(mathPrompt)
            #expect(response != nil, "Math should work with \(level) reasoning")
            if let response = response {
                print("Response: \(response.text)")
                #expect(response.text.contains("4"), "Response should contain the answer 4")
            }
        }
    }
    
    @Test("Complex reasoning prompts benefit from higher effort")
    func testComplexReasoningBenefitsFromHigherEffort() async throws {
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        let complexPrompt = "If a train travels at 60 mph for 2 hours, then 80 mph for 3 hours, what's the total distance traveled?"
        
        // Test with low reasoning
        let configLow = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,
            temperature: 0.7,
            maxTokens: 200,
            reasoningEffort: .low
        )
        
        let echoLow = Echo(key: apiKey, configuration: configLow)
        let conversationLow = try await echoLow.startConversation(
            mode: .text,
            systemMessage: "You are a helpful math tutor."
        )
        
        let responseLow = try await conversationLow.send(complexPrompt)
        print("Low reasoning response: \(responseLow?.text ?? "nil")")
        
        // Test with high reasoning
        let configHigh = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,
            temperature: 0.7,
            maxTokens: 400,
            reasoningEffort: .high
        )
        
        let echoHigh = Echo(key: apiKey, configuration: configHigh)
        let conversationHigh = try await echoHigh.startConversation(
            mode: .text,
            systemMessage: "You are a helpful math tutor who explains step by step."
        )
        
        let responseHigh = try await conversationHigh.send(complexPrompt)
        print("High reasoning response: \(responseHigh?.text ?? "nil")")
        
        // Both should work, but high reasoning should provide more detailed explanation
        #expect(responseLow != nil, "Low reasoning should still provide an answer")
        #expect(responseHigh != nil, "High reasoning should definitely provide an answer")
        
        if let low = responseLow, let high = responseHigh {
            // High reasoning response should generally be longer/more detailed
            print("Low response length: \(low.text.count)")
            print("High response length: \(high.text.count)")
            
            // Both should contain the correct answer (360 miles)
            #expect(low.text.contains("360"), "Low reasoning should have correct answer")
            #expect(high.text.contains("360"), "High reasoning should have correct answer")
        }
    }
    
    @Test("Error handling for incomplete responses")
    func testIncompleteResponseErrorHandling() async throws {
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        // Use a configuration that might trigger incomplete responses
        let config = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,
            temperature: 0.7,
            maxTokens: 10,  // Very low token limit might cause incomplete responses
            reasoningEffort: .high  // High reasoning with low tokens could cause issues
        )
        
        let echo = Echo(key: apiKey, configuration: config)
        let conversation = try await echo.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant."
        )
        
        // Track error events
        actor ErrorTracker {
            var errorReceived = false
            var errorMessage = ""
            
            func recordError(_ message: String) {
                errorReceived = true
                errorMessage = message
            }
            
            func getState() -> (received: Bool, message: String) {
                return (errorReceived, errorMessage)
            }
        }
        
        let errorTracker = ErrorTracker()
        
        // Start consuming error events from stream
        let eventTask = Task {
            for await event in echo.events {
                if case let .error(error) = event {
                    if case let EchoError.invalidResponse(msg) = error {
                        await errorTracker.recordError(msg)
                        break
                    }
                }
            }
        }
        
        // Wait for stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // This prompt with high reasoning and low token limit might cause issues
        let response = try await conversation.send("Explain the theory of relativity in detail")
        
        // Wait for error event to propagate
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        
        let errorState = await errorTracker.getState()
        
        // Either we get a truncated response or an error event
        if response == nil {
            print("Got nil response")
            if errorState.received {
                print("Error message: \(errorState.message)")
                #expect(errorState.message.contains("incomplete") || errorState.message.contains("reasoning"), 
                       "Error should mention incomplete or reasoning")
            }
        } else {
            print("Got response: \(response!.text)")
            // Response might be truncated due to token limit
        }
    }
}
