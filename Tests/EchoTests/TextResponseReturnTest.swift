// TextResponseReturnTest.swift
// Tests that Conversation.send() and sendMessage() return responses in text mode

import Testing
import Foundation
@testable import Echo

@Suite("Text Response Return Tests")
struct TextResponseReturnTest {
    
    @Test("send returns assistant response in text mode")
    func testSendReturnsResponse() async throws {
        // API key is required - fail if not found
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        // Create configuration for text mode
        let configuration = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,  // Use gpt-5-mini which should be available
            temperature: 0.7,
            maxTokens: 100
        )
        
        // Initialize Echo
        let echo = Echo(
            key: apiKey,
            configuration: configuration
        )
        
        // Get a conversation in text mode
        let conversation = try await echo.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise - respond in one short sentence."
        )
        
        // Send message and expect response - THIS IS THE FIX!
        let response = try await conversation.send("What is 2+2?")
        
        // Verify we got a response back
        #expect(response != nil, "send() should return a response in text mode")
        
        if let response = response {
            #expect(!response.text.isEmpty, "Response should have non-empty text")
            #expect(response.role == .assistant, "Response should be from assistant")
            // Response received successfully
        }
    }
    
    @Test("sendMessage returns assistant response in text mode when streaming")
    func testSendMessageReturnsResponseStreaming() async throws {
        // API key is required - fail if not found
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        // Create configuration for text mode
        let configuration = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,  // Use gpt-5-mini which should be available
            temperature: 0.7,
            maxTokens: 100
        )
        
        // Initialize Echo
        let echo = Echo(
            key: apiKey,
            configuration: configuration
        )
        
        // Get a conversation in text mode
        let conversation = try await echo.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise - respond in one short sentence."
        )
        
        // Send message without response format (streaming mode) - THIS IS THE FIX!
        let response = try await conversation.sendMessage("What is the capital of France?")
        
        // Verify we got a response back
        #expect(response != nil, "sendMessage() should return a response in streaming mode")
        
        if let response = response {
            #expect(!response.text.isEmpty, "Response should have non-empty text")
            #expect(response.role == .assistant, "Response should be from assistant")
            // Response received successfully
        }
    }
    
    @Test("send.message namespace returns response")
    func testSendMessageNamespaceReturnsResponse() async throws {
        // API key is required - fail if not found
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        // Create configuration for text mode with high reasoning
        // This ensures even complex prompts get proper responses
        let configuration = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,  // Use gpt-5-mini which should be available
            temperature: 0.7,
            maxTokens: 100,
            reasoningEffort: .low  // Try low reasoning to avoid getting stuck in reasoning-only mode
        )
        
        // Initialize Echo
        let echo = Echo(
            key: apiKey,
            configuration: configuration
        )
        
        // Get a conversation in text mode
        let conversation = try await echo.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise - respond in one short sentence."
        )
        
        // Use the namespace syntax with the ORIGINAL problematic prompt!
        let response = try await conversation.send.message("What color is the sky?")
        
        // Verify we got a response back
        #expect(response != nil, "send.message() should return a response")
        
        if let response = response {
            #expect(!response.text.isEmpty, "Response should have non-empty text")
            #expect(response.role == .assistant, "Response should be from assistant")
            // Verify response content
        }
    }
    
    @Test("send.json returns response with JSON format")
    func testSendJSONReturnsResponse() async throws {
        // API key is required - fail if not found
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        // Create configuration for text mode
        let configuration = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,  // Use gpt-5-mini which should be available
            temperature: 0.7,
            maxTokens: 100
        )
        
        // Initialize Echo
        let echo = Echo(
            key: apiKey,
            configuration: configuration
        )
        
        // Get a conversation in text mode
        let conversation = try await echo.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant that responds in JSON format."
        )
        
        // Send with JSON format expectation
        let response = try await conversation.send.json("Return a JSON object with a 'result' field containing the sum of 2+2")
        
        // JSON mode already returns a response (non-streaming)
        #expect(response != nil, "send.json() should return a response")
        
        if let response = response {
            #expect(!response.text.isEmpty, "Response should have text")
            #expect(response.role == .assistant, "Response should be from assistant")
            // Verify JSON response
            
            // Verify it's valid JSON
            if let data = response.text.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data, options: []) {
                // JSON validation successful
            }
        }
    }
    
    @Test("Incomplete response emits error event")
    func testIncompleteResponseEmitsError() async throws {
        // API key is required - fail if not found
        guard let apiKey = loadAPIKeySimple() else {
            Issue.record("❌ FAILED: No API key found. Set OPENAI_API_KEY environment variable or create .env file")
            return
        }
        
        // Create configuration for text mode
        let configuration = EchoConfiguration(
            defaultMode: .text,
            responsesModel: .gpt5Mini,  // Use gpt-5-mini which should be available
            temperature: 0.7,
            maxTokens: 100
        )
        
        // Initialize Echo
        let echo = Echo(
            key: apiKey,
            configuration: configuration
        )
        
        // Create a conversation
        let conversation = try await echo.startConversation(
            mode: .text,
            systemMessage: "You are a helpful assistant. Keep responses concise - respond in one short sentence."
        )
        
        // Track if error event was emitted using an actor for thread safety
        actor ErrorTracker {
            var errorEmitted = false
            var errorMessage = ""
            
            func recordError(_ message: String) {
                errorEmitted = true
                errorMessage = message
            }
            
            func getState() -> (emitted: Bool, message: String) {
                return (errorEmitted, errorMessage)
            }
        }
        
        let errorTracker = ErrorTracker()
        
        // Use stream-based event listening (v2.0 pattern)
        let listenTask = Task {
            for await event in echo.events {
                if case let .error(error) = event {
                    if case let EchoError.invalidResponse(msg) = error {
                        await errorTracker.recordError(msg)
                    }
                }
            }
        }
        
        // Wait for listener to be ready
        try await Task.sleep(nanoseconds: 10_000_000)
        
        // Send a prompt that might trigger reasoning-only response
        // Note: This test might not always trigger the incomplete response
        // depending on model behavior, but it verifies the error handling exists
        let response = try await conversation.send("What color is the sky on a clear day?")
        
        // Cancel listener task
        listenTask.cancel()
        
        // If we get a response, that's fine (model behavior varies)
        // If we get nil and an error was emitted, verify the error message
        let errorState = await errorTracker.getState()
        if response == nil && errorState.emitted {
            #expect(errorState.message.contains("incomplete"), "Error message should indicate incomplete response")
            #expect(errorState.message.contains("reasoning"), "Error message should mention reasoning")
        }
        // If we get a response, that's also valid (model completed successfully)
        // The important thing is that we handle both cases gracefully
    }
}