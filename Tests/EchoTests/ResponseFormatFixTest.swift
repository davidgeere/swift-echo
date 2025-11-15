// Test for response_format parameter fix
import Testing
import Foundation
@testable import Echo

@Suite("Response Format Fix Test")
struct ResponseFormatFixTest {
    
    @Test("Test JSON mode with fixed text.format parameter")
    func testJSONModeWithTextFormat() async throws {
        guard let apiKey = loadAPIKeyForResponseFormat() else {
            print("⚠️ Skipping: No API key found")
            return
        }
        
        print("🔑 Using API key: \(apiKey.prefix(10))...")
        
        let echo = Echo(key: apiKey)
        
        // Test 1: JSON mode - this was broken before the fix
        print("\n📝 Test 1: JSON mode with conversation...")
        
        let conversation = try await echo.start.conversation(mode: .text)
        
        // Send a message expecting JSON response
        let message = try await conversation.send.json("Generate a JSON object with name and age for John who is 30")
        
        print("✅ Got JSON response:")
        if let text = message?.text {
            print("   Response: \(text)")
            // Verify it's valid JSON
            guard let data = text.data(using: .utf8),
                  let _ = try? JSONSerialization.jsonObject(with: data, options: []) else {
                Issue.record("Response is not valid JSON: \(text)")
                return
            }
            print("✅ Valid JSON confirmed!")
        } else {
            Issue.record("No response received")
        }
        
        // Test 2: JSON mode with Conversation.send.message
        print("\n📝 Test 2: JSON mode with explicit format...")
        
        let conversation2 = try await echo.start.conversation(mode: .text)
        let message2 = try await conversation2.send.message(
            "Generate a JSON array with numbers 1, 2, 3",
            expecting: .jsonObject
        )
        
        if let text2 = message2?.text {
            print("✅ Got JSON response:")
            print("   Response: \(text2)")
            // Verify it's valid JSON
            guard let data2 = text2.data(using: .utf8),
                  let _ = try? JSONSerialization.jsonObject(with: data2, options: []) else {
                Issue.record("Response is not valid JSON: \(text2)")
                return
            }
            print("✅ Valid JSON array confirmed!")
        } else {
            Issue.record("No response received")
        }
        
        // Note: Structured output with automatic schema generation has a separate issue
        // (empty schema generation) that's unrelated to the response_format fix
        
        print("\n🎉 Response format fix verified - text.format parameter working for JSON mode!")
    }
}

func loadAPIKeyForResponseFormat() -> String? {
    if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
        return key
    }
    
    let paths = [".env", "../.env", "../../.env"]
    for path in paths {
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("OPENAI_API_KEY=") {
                    return trimmed.replacingOccurrences(of: "OPENAI_API_KEY=", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
    }
    
    return nil
}
