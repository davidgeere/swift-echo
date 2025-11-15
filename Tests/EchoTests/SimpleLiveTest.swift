// Simple live test that works with Swift Testing
import Testing
import Foundation
@testable import Echo

@Suite("Live API Test")
struct SimpleLiveTest {
    
    @Test("Test live embeddings API")
    func testLiveAPI() async throws {
        // Load API key from .env or environment
        guard let apiKey = loadAPIKeySimple() else {
            // Skip test if no API key
            print("⚠️ Skipping: No API key found in .env or environment")
            return
        }
        
        print("🔑 Using API key: \(apiKey.prefix(10))...")
        
        let echo = Echo(key: apiKey)
        
        // Test 1: Single embedding
        print("📝 Test 1: Single embedding...")
        let embedding = try await echo.generate.embedding(from: "Hello, world!")
        print("✅ Got \(embedding.count) dimensions")
        #expect(embedding.count == 1536)
        
        // Test 2: Batch embeddings  
        print("📝 Test 2: Batch embeddings...")
        let embeddings = try await echo.generate.embeddings(
            from: ["Text 1", "Text 2"],
            model: .textEmbedding3Small
        )
        print("✅ Got \(embeddings.count) embeddings")
        #expect(embeddings.count == 2)
        
        // Test 3: Find similar
        print("📝 Test 3: Find similar...")
        let results = try await echo.find.similar(
            to: "dog",
            in: ["cat", "puppy", "car"],
            topK: 2
        )
        print("✅ Found \(results.count) similar texts")
        #expect(results.count == 2)
        print("   Most similar: '\(results[0].text)' (score: \(results[0].similarity))")
        
        print("\n🎉 All live tests passed!")
    }
}

// Simple helper that doesn't conflict
func loadAPIKeySimple() -> String? {
    // Try environment first
    if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
        return key
    }
    
    // Try .env file
    let paths = [".env", "../.env", "../../.env"]
    for path in paths {
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("OPENAI_API_KEY=") {
                    let key = trimmed.replacingOccurrences(of: "OPENAI_API_KEY=", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !key.isEmpty { return key }
                }
            }
        }
    }
    
    return nil
}
