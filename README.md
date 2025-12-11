# 🔊 Echo

A unified Swift library for OpenAI's Realtime API (WebSocket-based voice) and Chat API with a beautiful conversational interface.

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2018%20|%20macOS%2014-blue.svg)](https://developer.apple.com)
[![Version](https://img.shields.io/badge/version-1.6.1-brightgreen.svg)](https://github.com/davidgeere/swift-echo/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 🚀 Latest Updates

**Echo v1.6.0** adds Echo Protection for speaker mode:

- **Semantic VAD**: Meaning-based speech detection with eagerness control (low/medium/high)
- **Server-Side Noise Reduction**: Near-field and far-field modes for echo filtering
- **Client-Side Audio Gating**: Filters low-level audio during assistant speech
- **Automatic VAD Switching**: Adjusts settings based on audio output device
- **Smart Audio Output**: `.smart` device type auto-selects Bluetooth or speaker with protection

**Echo v1.5.0** added FFT-based audio frequency analysis with real-time level monitoring.

[View changelog →](CHANGELOG.md)

## ✨ Features

- 🎙️ **Voice Conversations** - Real-time voice chat using OpenAI's Realtime API
- 💬 **Text Chat** - Traditional text-based conversations with streaming support  
- 📊 **Audio Level Monitoring** - Real-time frequency analysis with low/mid/high bands
- 🧮 **Embeddings API** - Generate text embeddings for semantic search and similarity
- 📋 **Structured Output** - Type-safe JSON generation with Codable schemas
- 🔄 **Seamless Mode Switching** - Switch between voice and text mid-conversation
- 🎯 **Conversational API** - Beautiful, discoverable API design
- 🛠️ **Tool Calling** - Function calling with MCP server support
- 📈 **Event-Driven** - Comprehensive event system for all interactions

## 🚀 Installation

Add Echo to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/davidgeere/swift-echo.git", from: "1.6.0")
]
```

## 🎯 Quick Start

### Initialize Echo

```swift
import Echo

let echo = Echo(
    key: "your-openai-api-key",
    configuration: .default
)
```

### 💬 Text Conversations

```swift
// Start a conversation
let conversation = try await echo.startConversation(
    mode: .text,
    systemMessage: "You are a helpful assistant."
)

// Send messages
try await conversation.send("Hello! How are you?")

// Stream responses
for await message in conversation.messages {
    print("\(message.role): \(message.text)")
}
```

### 🎙️ Voice Conversations

```swift
// Start voice mode with automatic turn detection (VAD)
let conversation = try await echo.startConversation(mode: .audio)

// The conversation handles audio I/O automatically
// User speaks → AI responds → User speaks...
// VAD automatically detects when you stop speaking

// Switch to text anytime
try await conversation.switchMode(to: .text)

// List available audio output devices
let devices = await conversation.availableAudioOutputDevices
// Returns: [.builtInSpeaker, .builtInReceiver, .bluetooth(name: "AirPods Pro"), .bluetooth(name: "External Speaker")]

// Get current active output device
let current = await conversation.currentAudioOutput
// Returns: .bluetooth(name: "AirPods Pro") or .builtInSpeaker, etc.

// Set audio output device
try await conversation.setAudioOutput(device: .builtInSpeaker)  // Force speaker
try await conversation.setAudioOutput(device: .builtInReceiver)  // Force earpiece
try await conversation.setAudioOutput(device: .bluetooth)       // Allow Bluetooth (system chooses active device)
try await conversation.setAudioOutput(device: .wiredHeadphones) // Allow wired headphones
try await conversation.setAudioOutput(device: .systemDefault)    // Let system choose

// Listen for audio output changes via events stream
Task {
    for await event in echo.events {
        if case .audioOutputChanged(let device) = event {
            print("Audio output changed to: \(device.description)")
        }
    }
}

// Control mute state
conversation.setMuted(true)   // Mute microphone
conversation.setMuted(false)  // Unmute microphone
```

### 🔊 Echo Protection for Speaker Mode

When using speaker output, the AI can hear itself and interrupt its own responses. Echo v1.6.0 solves this with a multi-layered approach:

```swift
// Simple: Use the speaker-optimized preset
let config = EchoConfiguration.speakerOptimized
let echo = Echo(key: apiKey, configuration: config)

// This preset includes:
// - Semantic VAD with low eagerness (waits longer before responding)
// - Far-field noise reduction (filters speaker echo)
// - Client-side audio gating (blocks low-level sounds during speech)
// - Smart audio output (Bluetooth if available, speaker otherwise)
```

#### Custom Echo Protection

```swift
// Fine-tune echo protection for your environment
let config = EchoConfiguration(
    defaultMode: .audio,
    defaultAudioOutput: .smart,  // Auto-select best device
    inputAudioConfiguration: .farField,  // Server-side noise reduction
    echoProtection: EchoProtectionConfiguration(
        bargeInThreshold: 0.15,  // RMS level to allow interruption
        postSpeechDelay: .milliseconds(300)  // Delay after speech ends
    ),
    turnDetection: .automatic(.speakerOptimized)  // Semantic VAD
)

let echo = Echo(key: apiKey, configuration: config)
```

#### Semantic VAD with Eagerness Control

Semantic VAD uses meaning-based detection instead of just volume:

```swift
// Low eagerness: Waits longer, best for speaker mode
let speakerVAD = VADConfiguration(
    type: .semanticVAD,
    eagerness: .low,
    interruptResponse: true,
    createResponse: true
)

// High eagerness: Responds quickly, good for earpiece/headphones
let earpieceVAD = VADConfiguration(
    type: .serverVAD,
    threshold: 0.5,
    silenceDurationMs: 500,
    prefixPaddingMs: 300
)

let config = EchoConfiguration(
    turnDetection: .automatic(speakerVAD)
)
```

#### Understanding Echo Protection Presets

| Preset | Use Case | VAD Type | Eagerness | Noise Reduction |
|--------|----------|----------|-----------|-----------------|
| `.speakerOptimized` | Speaker output | Semantic | Low | Far-field |
| `.earpiece` | Earpiece/receiver | Server | High | Near-field |
| `.bluetooth` | Bluetooth devices | Semantic | Medium | Far-field |
| `.default` | General use | Server | Medium | Near-field |

#### Audio Output Device Selection

Echo automatically adjusts VAD settings based on the output device:

```swift
// Speaker mode - enables echo protection automatically
try await conversation.setAudioOutput(device: .builtInSpeaker)

// Earpiece mode - uses faster VAD response
try await conversation.setAudioOutput(device: .builtInReceiver)

// Smart mode - Bluetooth if available, speaker with protection otherwise
try await conversation.setAudioOutput(device: .smart)

// Check if current device may produce echo
let current = await conversation.currentAudioOutput
if current.mayProduceEcho {
    // Speaker or Bluetooth - echo protection active
}
```

### 📊 Audio Level Monitoring

Monitor audio input and output levels with frequency band analysis:

```swift
// Observable properties update automatically in SwiftUI views
struct AudioVisualizerView: View {
    let conversation: Conversation
    
    var body: some View {
        VStack {
            // Input (microphone) levels
            Text("Input: \(conversation.inputLevels.level, specifier: "%.2f")")
            HStack {
                Text("Low: \(conversation.inputLevels.low, specifier: "%.2f")")
                Text("Mid: \(conversation.inputLevels.mid, specifier: "%.2f")")
                Text("High: \(conversation.inputLevels.high, specifier: "%.2f")")
            }
            
            // Output (speaker) levels
            Text("Output: \(conversation.outputLevels.level, specifier: "%.2f")")
            HStack {
                Text("Low: \(conversation.outputLevels.low, specifier: "%.2f")")
                Text("Mid: \(conversation.outputLevels.mid, specifier: "%.2f")")
                Text("High: \(conversation.outputLevels.high, specifier: "%.2f")")
            }
        }
    }
}

// Or use events for more control
Task {
    for await event in echo.events {
        switch event {
        case .inputLevelsChanged(let levels):
            // Update input visualizer
            print("Input - Level: \(levels.level), Low: \(levels.low), Mid: \(levels.mid), High: \(levels.high)")
        case .outputLevelsChanged(let levels):
            // Update output visualizer
            print("Output - Level: \(levels.level)")
        default:
            break
        }
    }
}
```

**AudioLevels Properties:**
- `level` - Overall RMS amplitude (0.0-1.0)
- `low` - Low frequency band energy, 20-250 Hz (bass, rumble)
- `mid` - Mid frequency band energy, 250-4000 Hz (voice, melody)
- `high` - High frequency band energy, 4000-20000 Hz (sibilance, air)

## 🧮 Embeddings API

Generate embeddings for semantic search, similarity matching, and more!

### Single Embedding

```swift
// Generate a single embedding
let embedding = try await echo.generate.embedding(
    from: "Swift is a powerful programming language"
)
// Returns [Float] with 1536 dimensions (default)
```

### Batch Embeddings

```swift
// Process multiple texts at once
let embeddings = try await echo.generate.embeddings(
    from: ["Document 1", "Document 2", "Document 3"],
    model: .textEmbedding3Large  // 3072 dimensions
)
```

### Find Similar Texts

```swift
// Find semantically similar texts from a corpus
let corpus = [
    "The quick brown fox jumps over the lazy dog",
    "A fast auburn canine leaps above a sleepy hound", 
    "Python is a programming language",
    "Swift is a modern programming language"
]

let results = try await echo.find.similar(
    to: "Tell me about Swift programming",
    in: corpus,
    topK: 2
)

// Results sorted by similarity
for result in results {
    print("\(result.text) - Similarity: \(result.similarity)")
}
// Output:
// "Swift is a modern programming language" - Similarity: 0.825
// "Python is a programming language" - Similarity: 0.743
```

### Custom Dimensions

```swift
// Use custom dimensions for specific models
let embedding = try await echo.generate.embedding(
    from: "Optimize for size",
    model: .textEmbedding3Small,
    dimensions: 512  // Reduce from 1536 to 512
)
```

### Available Models

- `textEmbedding3Small` - 1536 dimensions (default, best balance)
- `textEmbedding3Large` - 3072 dimensions (highest accuracy)
- `textEmbeddingAda002` - 1536 dimensions (legacy)

## 📋 Structured Output

Generate type-safe JSON responses that conform to your schemas!

### JSON Mode

```swift
// Request JSON formatted response
let jsonResponse = try await conversation.send("Generate a user profile for Alice, age 30")
// Returns valid JSON string
```

### Type-Safe Structured Output

```swift
// Define your schema with Codable
struct UserProfile: Codable, Sendable {
    let name: String
    let age: Int
    let email: String
    let interests: [String]
}

// Generate structured data - type-safe and validated!
let profile = try await echo.generate.structured(
    UserProfile.self,
    from: "Create a profile for Bob Smith, 28, bob@example.com, likes Swift and AI"
)

print(profile.name)       // "Bob Smith"
print(profile.age)        // 28
print(profile.interests)  // ["Swift", "AI"]
```

### Complex Schemas

```swift
struct TodoList: Codable, Sendable {
    struct TodoItem: Codable, Sendable {
        let id: String
        let title: String
        let completed: Bool
        let priority: Priority
        
        enum Priority: String, Codable {
            case low, medium, high
        }
    }
    
    let title: String
    let items: [TodoItem]
    let createdAt: Date
}

// Generate complex nested structures
let todoList = try await echo.generate.structured(
    TodoList.self,
    from: "Create a todo list for launching a new app with 3 tasks"
)
```

## 🔄 Mode Switching

Switch seamlessly between voice and text while preserving context:

```swift
// Start in text mode
let conversation = try await echo.startConversation(mode: .text)
try await conversation.send("Let's discuss Swift")

// Switch to voice - context preserved!
try await conversation.switchMode(to: .audio)
// Continue conversation with voice...

// Switch back to text anytime
try await conversation.switchMode(to: .text)
// Previous context still available
```

## 🛠️ Tool Calling

Register functions that the AI can call:

```swift
// Define a tool
let weatherTool = Tool(
    name: "get_weather",
    description: "Get current weather for a location",
    parameters: [
        "location": ["type": "string", "description": "City name"]
    ]
) { args in
    let location = args["location"] as? String ?? "Unknown"
    return "It's 72°F and sunny in \(location)"
}

// Register the tool
echo.registerTool(weatherTool)

// AI will automatically call tools when needed
try await conversation.send("What's the weather in San Francisco?")
// AI calls get_weather("San Francisco") and responds with the result
```

## 📊 Event System

Observe all events via the `events` AsyncStream:

### Events Stream

```swift
// Observe events via async stream
Task {
    for await event in echo.events {
        switch event {
        case .messageFinalized(let message):
            print("New message: \(message.text)")
            
        case .userStartedSpeaking:
            print("🎙️ User is speaking...")
            
        case .assistantStartedSpeaking:
            print("🤖 Assistant is responding...")
            
        case .userTranscriptionCompleted(let transcript, _):
            print("User said: \(transcript)")
            
        case .audioOutputChanged(let device):
            print("Audio output changed to: \(device.description)")
            
        case .error(let error):
            print("Error: \(error)")
            
        default:
            break
        }
    }
}
```

### Multiple Observers

Create multiple Tasks to handle events in different ways:

```swift
// UI updates on MainActor
Task { @MainActor in
    for await event in echo.events {
        switch event {
        case .userStartedSpeaking:
            updateMicrophoneIndicator(active: true)
        case .userStoppedSpeaking:
            updateMicrophoneIndicator(active: false)
        case .assistantStartedSpeaking:
            showAssistantSpeaking()
        case .assistantStoppedSpeaking:
            hideAssistantSpeaking()
        default:
            break
        }
    }
}

// Logging in background
Task.detached(priority: .utility) {
    for await event in echo.events {
        Logger.log(event)
    }
}
```

### Audio Lifecycle Events

Track audio system startup and shutdown:

```swift
Task {
    for await event in echo.events {
        switch event {
        case .audioStarting:
            print("Connecting audio...")
            // Show "Connecting..." UI state
            
        case .audioStarted:
            print("Ready to speak!")
            // Show "Ready" UI state
            
        case .audioStopped:
            print("Audio disconnected")
            // Show "Disconnected" UI state
            
        default:
            break
        }
    }
}
```

### Filtering Events

Use Swift's pattern matching for selective handling:

```swift
Task {
    // Only handle audio-related events
    for await event in echo.events {
        switch event {
        case .audioStarted, .audioStopped, .inputLevelsChanged, .outputLevelsChanged:
            handleAudioEvent(event)
        default:
            break
        }
    }
}
```

## ⚙️ Configuration

Customize behavior with configuration:

```swift
let configuration = EchoConfiguration(
    realtimeModel: .gptRealtimeMini,     // For voice
    responsesModel: .gpt5,                // For text  
    temperature: 0.7,
    maxTokens: 2000,
    voice: .alloy,                        // Voice selection
    audioFormat: .pcm16,                  // Audio format
    defaultAudioOutput: .smart,           // Smart device selection
    inputAudioConfiguration: .farField,   // Noise reduction mode
    echoProtection: .default,             // Client-side echo gating
    turnDetection: .automatic(            // Voice activity detection
        VADConfiguration(
            type: .semanticVAD,
            eagerness: .low,
            interruptResponse: true,
            createResponse: true
        )
    )
)

let echo = Echo(key: apiKey, configuration: configuration)

// Or use a preset for common scenarios
let speakerConfig = EchoConfiguration.speakerOptimized
```

### 🎙️ Turn Detection Modes

Configure how voice conversations detect when users stop speaking:

```swift
// Server VAD - Volume-based detection
// Good for earpiece/headphones where echo isn't an issue
let serverVAD = VADConfiguration(
    type: .serverVAD,
    threshold: 0.5,
    silenceDurationMs: 500,
    prefixPaddingMs: 300,
    interruptResponse: true,
    createResponse: true
)

// Semantic VAD - Meaning-based detection (NEW in 1.6.0)
// Good for speaker mode - understands conversational context
let semanticVAD = VADConfiguration(
    type: .semanticVAD,
    eagerness: .low,      // .low, .medium, or .high
    interruptResponse: true,
    createResponse: true
)

// Use presets for common scenarios
configuration.turnDetection = .automatic(.speakerOptimized)  // Semantic, low eagerness
configuration.turnDetection = .automatic(.earpiece)          // Server VAD, high eagerness
configuration.turnDetection = .automatic(.bluetooth)         // Semantic, medium eagerness

// Manual - You control when turns end
// Call conversation.endUserTurn() to trigger response
configuration.turnDetection = .manual

// Disabled - No turn management
configuration.turnDetection = .disabled
```

#### VAD Eagerness Levels

| Eagerness | Behavior | Best For |
|-----------|----------|----------|
| `.low` | Waits longer before responding | Speaker mode, noisy environments |
| `.medium` | Balanced response time | Bluetooth, general use |
| `.high` | Responds quickly | Earpiece, quiet environments |

## 🎯 More Examples

### Semantic Search System

```swift
// Build a simple semantic search
class DocumentSearch {
    let echo: Echo
    var embeddings: [(text: String, vector: [Float])] = []
    
    // Index documents
    func indexDocuments(_ documents: [String]) async throws {
        let vectors = try await echo.generate.embeddings(from: documents)
        embeddings = zip(documents, vectors).map { ($0, $1) }
    }
    
    // Search
    func search(_ query: String, topK: Int = 5) async throws -> [String] {
        let queryEmbedding = try await echo.generate.embedding(from: query)
        
        // Calculate similarities
        let results = embeddings.map { doc in
            let similarity = cosineSimilarity(queryEmbedding, doc.vector)
            return (doc.text, similarity)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(topK)
        
        return results.map { $0.0 }
    }
}
```

### Content Generation with Structure

```swift
struct BlogPost: Codable, Sendable {
    let title: String
    let introduction: String
    let mainPoints: [String]
    let conclusion: String
    let tags: [String]
}

let post = try await echo.generate.structured(
    BlogPost.self,
    from: "Write a blog post about the future of AI in mobile development",
    instructions: "Make it technical but accessible, around 500 words"
)

print("Title: \(post.title)")
print("Tags: \(post.tags.joined(separator: ", "))")
```

## 🔧 Background Audio Support

Echo supports background audio playback, allowing conversations to continue when your app is in the background.

### App-Level Configuration

Add the `audio` background mode to your app's `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### Library Support

Echo automatically configures the audio session with `.playAndRecord` category, which supports background audio. No additional library configuration is needed - just add the background mode to your `Info.plist`.

**Note:** Background audio requires the app to be actively using audio. The system may suspend background audio if the app doesn't maintain an active audio session.

## 📱 Platform Requirements

- iOS 18.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## 📚 Documentation

For detailed documentation, see the [Architecture Specification](Echo%20-%20A%20Unified%20Swift%20Library%20and%20Architecture%20Document.md).

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

Echo is available under the MIT license. See the LICENSE file for more info.

---

**Questions?** Open an issue or reach out!

**Enjoying Echo?** Give it a ⭐️