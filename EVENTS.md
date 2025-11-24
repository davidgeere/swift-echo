# Echo Events Reference

Complete guide to all events emitted by Echo and how to leverage them using the `echo.when()` API.

## Table of Contents

- [User Speech Events](#user-speech-events)
- [Assistant Response Events](#assistant-response-events)
- [Audio Events](#audio-events)
  - [Audio Output Events](#audio-output-events)
- [Turn Events](#turn-events)
- [Tool Events](#tool-events)
- [Message Events](#message-events)
- [Connection Events](#connection-events)
- [Mode Events](#mode-events)
- [Embedding Events](#embedding-events)
- [Error Events](#error-events)

## Event Handler Syntax

Echo provides flexible ways to handle events:

### Single Event Handler

#### Synchronous Handler
```swift
echo.when(.eventType) { event in
    // Handle event synchronously
    // Access event values using pattern matching
}
```

#### Asynchronous Handler
```swift
echo.when(.eventType) { event in
    // Handle event asynchronously
    // Can perform async operations
    await someAsyncOperation()
}
```

### Multiple Events Handler

Listen to multiple events with a single handler using variadic parameters:

```swift
// Listen for multiple events with one handler (variadic syntax - recommended)
echo.when(.userStartedSpeaking, .assistantStartedSpeaking) { event in
    switch event {
    case .userStartedSpeaking:
        print("User started speaking")
    case .assistantStartedSpeaking:
        print("Assistant started speaking")
    default:
        break
    }
}
```

**Variadic Syntax (Recommended):**
```swift
echo.when(.eventTypeA, .eventTypeB, .eventTypeC) { event in
    // Handle any of the specified events
    // Use pattern matching to determine which event occurred
}
```

**Array Syntax (Also Supported):**
```swift
echo.when([.eventTypeA, .eventTypeB, .eventTypeC]) { event in
    // Handle any of the specified events
    // Use pattern matching to determine which event occurred
}
```

Both syntaxes are equivalent. The variadic syntax is more concise and Swift-idiomatic.

This is equivalent to registering the same handler multiple times, but more concise:

```swift
// Equivalent to:
echo.when(.userStartedSpeaking) { event in
    // handler code
}
echo.when(.assistantStartedSpeaking) { event in
    // same handler code
}
```

**Benefits:**
- Cleaner code when handling multiple events the same way
- Single handler definition instead of duplicating code
- Easier to maintain and update
- Reduces code duplication
- More readable with variadic syntax

---

## User Speech Events

### `.userStartedSpeaking`

**When:** VAD (Voice Activity Detection) detects that the user has started speaking.

**Event Value:** None (no associated data)

**Use Case:** Update UI to show user is speaking, start visual feedback, pause background audio.

```swift
echo.when(.userStartedSpeaking) { event in
    // Update UI to show user is speaking
    print("User started speaking")
    // Show microphone indicator, pause music, etc.
}
```

---

### `.userStoppedSpeaking`

**When:** VAD detects that the user has stopped speaking.

**Event Value:** None (no associated data)

**Use Case:** Hide speaking indicators, prepare for assistant response.

```swift
echo.when(.userStoppedSpeaking) { event in
    // User finished speaking
    print("User stopped speaking")
    // Hide microphone indicator, show processing indicator
}
```

---

### `.userAudioBufferCommitted`

**When:** User audio buffer has been committed to the conversation (creates a message slot).

**Event Value:** 
- `itemId: String` - The conversation item ID assigned by the API

**Use Case:** Track conversation items, link audio to messages, maintain conversation state.

```swift
echo.when(.userAudioBufferCommitted) { event in
    guard case .userAudioBufferCommitted(let itemId) = event else { return }
    
    print("User audio committed with item ID: \(itemId)")
    // Store itemId for later reference
    // Link this itemId to the message when transcription completes
}
```

---

### `.userTranscriptionCompleted`

**When:** User speech has been transcribed and the transcript is ready.

**Event Value:**
- `transcript: String` - The completed transcript text
- `itemId: String` - The conversation item ID for this transcript

**Use Case:** Display transcript in UI, store conversation history, perform actions based on user input.

```swift
echo.when(.userTranscriptionCompleted) { event in
    guard case .userTranscriptionCompleted(let transcript, let itemId) = event else { return }
    
    print("User said: \(transcript)")
    print("Item ID: \(itemId)")
    
    // Display transcript in chat UI
    // Store in conversation history
    // Perform actions based on transcript content
}
```

---

## Assistant Response Events

### `.assistantResponseCreated`

**When:** Assistant response has been created (starts a message slot).

**Event Value:**
- `itemId: String` - The response item ID

**Use Case:** Track assistant responses, prepare UI for incoming content, link responses to messages.

```swift
echo.when(.assistantResponseCreated) { event in
    guard case .assistantResponseCreated(let itemId) = event else { return }
    
    print("Assistant response created with item ID: \(itemId)")
    // Create message slot in UI
    // Track this itemId for the response
}
```

---

### `.assistantStartedSpeaking`

**When:** Assistant has started speaking/responding.

**Event Value:** None (no associated data)

**Use Case:** Update UI to show assistant is speaking, pause user input, show speaking indicator.

```swift
echo.when(.assistantStartedSpeaking) { event in
    print("Assistant started speaking")
    // Show speaking indicator
    // Disable user input
    // Update audio status UI
}
```

---

### `.assistantStoppedSpeaking`

**When:** Assistant has finished speaking/responding.

**Event Value:** None (no associated data)

**Use Case:** Hide speaking indicators, re-enable user input, prepare for next turn.

```swift
echo.when(.assistantStoppedSpeaking) { event in
    print("Assistant stopped speaking")
    // Hide speaking indicator
    // Re-enable user input
    // Show listening state
}
```

---

### `.assistantResponseDone`

**When:** Assistant response is complete (finalizes the message).

**Event Value:**
- `itemId: String` - The response item ID
- `text: String` - The complete response text

**Use Case:** Display final response, store complete message, perform post-response actions.

```swift
echo.when(.assistantResponseDone) { event in
    guard case .assistantResponseDone(let itemId, let text) = event else { return }
    
    print("Assistant response complete:")
    print("Item ID: \(itemId)")
    print("Text: \(text)")
    
    // Display final response in UI
    // Store complete message
    // Perform any post-response actions
}
```

---

### `.assistantTextDelta`

**When:** A streaming text chunk is received from the assistant (during text generation).

**Event Value:**
- `delta: String` - The incremental text chunk

**Use Case:** Stream text to UI in real-time, build up response incrementally, show typing indicators.

```swift
echo.when(.assistantTextDelta) { event in
    guard case .assistantTextDelta(let delta) = event else { return }
    
    // Append delta to UI
    print("Received text chunk: \(delta)")
    // Update streaming text display
    // Show typing indicator
}
```

**Note:** This event fires multiple times during a single response as text streams in.

---

### `.assistantAudioDelta`

**When:** An audio chunk is received from the assistant (during audio streaming).

**Event Value:**
- `audioChunk: Data` - The audio data chunk

**Use Case:** Stream audio playback, visualize audio waveform, buffer audio for playback.

```swift
echo.when(.assistantAudioDelta) { event in
    guard case .assistantAudioDelta(let audioChunk) = event else { return }
    
    print("Received audio chunk: \(audioChunk.count) bytes")
    // Stream to audio player
    // Visualize waveform
    // Buffer for playback
}
```

**Note:** This event fires multiple times during a single audio response as audio streams in.

---

## Audio Events

### `.audioLevelChanged`

**When:** Audio input level has changed (useful for visualizations).

**Event Value:**
- `level: Double` - Audio level from 0.0 (silent) to 1.0 (loudest)

**Use Case:** Visualize microphone input level, show audio waveform, provide audio feedback.

```swift
echo.when(.audioLevelChanged) { event in
    guard case .audioLevelChanged(let level) = event else { return }
    
    // Update audio level visualization
    let percentage = Int(level * 100)
    print("Audio level: \(percentage)%")
    
    // Update UI bar/indicator
    // Animate waveform visualization
}
```

**Note:** This event fires frequently during audio input. Consider throttling UI updates.

---

### `.audioStatusChanged`

**When:** Audio status has changed (listening, speaking, processing, idle).

**Event Value:**
- `status: AudioStatus` - The new audio status

**AudioStatus Values:**
- `.listening` - System is listening for user input
- `.speaking` - Assistant is speaking
- `.processing` - System is processing (thinking)
- `.idle` - System is idle

**Use Case:** Update UI state, show appropriate indicators, manage audio session.

```swift
echo.when(.audioStatusChanged) { event in
    guard case .audioStatusChanged(let status) = event else { return }
    
    switch status {
    case .listening:
        print("Status: Listening for user input")
        // Show listening indicator
        // Enable microphone
        
    case .speaking:
        print("Status: Assistant is speaking")
        // Show speaking indicator
        // Disable microphone
        
    case .processing:
        print("Status: Processing/thinking")
        // Show processing indicator
        // Disable input
        
    case .idle:
        print("Status: Idle")
        // Show idle state
        // Reset UI indicators
    }
}
```

---

### `.audioStarting`

**When:** Audio system setup has begun (emitted at the start of `startAudio()`).

**Event Value:** None (no associated data)

**Use Case:** Show UI feedback that audio is being initialized (e.g., "Connecting audio...", spinner, etc.). This event is emitted before any audio capture or playback setup begins, allowing UI to provide immediate feedback during the connection period.

**Note:** This event is distinct from `connectionStatusChanged` which tracks network connection (WebSocket/HTTP). This tracks the audio system lifecycle.

```swift
echo.when(.audioStarting) { event in
    print("Audio system is starting...")
    // Show loading indicator
    // Update UI: "Connecting audio..."
    // Disable microphone button until audioStarted
}
```

---

### `.audioStarted`

**When:** Audio capture and playback are fully ready and operational.

**Event Value:** None (no associated data)

**Use Case:** Enable microphone input, show that audio is ready, update UI to indicate the system is ready for conversation. This is emitted after both audio capture and playback have been successfully started.

```swift
echo.when(.audioStarted) { event in
    print("Audio system is ready!")
    // Hide loading indicator
    // Update UI: "Ready to speak"
    // Enable microphone button
    // Show audio level visualization
}
```

---

### `.audioStopped`

**When:** Audio system has stopped (either explicitly stopped or failed during setup).

**Event Value:** None (no associated data)

**Use Case:** Disable microphone input, show that audio is no longer available, clean up UI state. This event is emitted when:
- Audio is explicitly stopped via `stopAudio()` or `disconnect()`
- Audio setup fails (permission denied, format error, etc.)

**Note:** This event is distinct from `muted` state (controlled via `setMuted()`). `audioStopped` indicates the audio system is no longer running, while `muted` indicates audio is running but input is disabled.

```swift
echo.when(.audioStopped) { event in
    print("Audio system has stopped")
    // Hide audio level visualization
    // Update UI: "Audio disconnected"
    // Disable microphone button
    // Show reconnection option if needed
}
```

---

### `.audioOutputChanged`

**When:** Audio output device has changed (either programmatically or via system controls).

**Event Value:**
- `device: AudioOutputDeviceType` - The new active audio output device

**AudioOutputDeviceType Values:**
- `.builtInSpeaker` - Built-in speaker
- `.builtInReceiver` - Earpiece/receiver
- `.bluetooth(name: String?)` - Bluetooth device (with optional device name)
- `.wiredHeadphones(name: String?)` - Wired headphones (with optional device name)
- `.systemDefault` - System default route

**Use Case:** Update UI to show current audio output device, display device name in UI, handle device switching.

```swift
echo.when(.audioOutputChanged) { event in
    guard case .audioOutputChanged(let device) = event else { return }
    
    print("Audio output changed to: \(device.description)")
    
    switch device {
    case .builtInSpeaker:
        // Update UI: "Speaker"
        // Show speaker icon
        
    case .builtInReceiver:
        // Update UI: "Earpiece"
        // Show earpiece icon
        
    case .bluetooth(let name):
        // Update UI: name ?? "Bluetooth"
        // Show Bluetooth icon
        // Display device name if available
        
    case .wiredHeadphones(let name):
        // Update UI: name ?? "Headphones"
        // Show headphones icon
        
    case .systemDefault:
        // Update UI: "System Default"
        // Show default icon
    }
}
```

**Note:** This event is emitted:
- When `setAudioOutput()` is called programmatically
- When the user switches audio output via system controls (Control Center, Settings, etc.)
- Allows UI to stay in sync with actual audio routing

**Example: Tracking Audio Output**

```swift
var currentOutput: AudioOutputDeviceType = .systemDefault

echo.when(.audioOutputChanged) { event in
    guard case .audioOutputChanged(let device) = event else { return }
    currentOutput = device
    
    // Update UI with current device
    updateAudioOutputUI(device: device)
}

// Programmatically change output
try await conversation.setAudioOutput(device: .bluetooth)

// Event will fire automatically
// UI will update to show Bluetooth device
```

---

**Example: Tracking Audio Lifecycle**

```swift
// Track the full audio lifecycle during conversation startup
var audioState: String = "disconnected"

echo.when(.audioStarting) { _ in
    audioState = "starting"
    print("Audio: Starting...")
    // Show: "Connecting audio..."
}

echo.when(.audioStarted) { _ in
    audioState = "started"
    print("Audio: Ready!")
    // Show: "Ready to speak"
}

echo.when(.audioStopped) { _ in
    audioState = "stopped"
    print("Audio: Stopped")
    // Show: "Audio disconnected"
}

// Start conversation - events will fire in sequence
let conv = try await echo.startConversation(mode: .audio)
// Expected sequence:
// 1. connectionStatusChanged(isConnected: true) - WebSocket connected
// 2. audioStarting - Audio setup begins
// 3. audioStarted - Audio ready
```

---

## Turn Events

### `.turnChanged`

**When:** Speaking turn has changed between user and assistant.

**Event Value:**
- `speaker: TurnManager.Speaker` - The current speaker

**Speaker Values:**
- `.user` - User is speaking
- `.assistant` - Assistant is speaking
- `.none` - No one is speaking

**Use Case:** Track conversation flow, update UI based on who's speaking, manage turn-based logic.

```swift
echo.when(.turnChanged) { event in
    guard case .turnChanged(let speaker) = event else { return }
    
    switch speaker {
    case .user:
        print("Turn: User is speaking")
        // Update UI for user turn
        // Show user indicators
        
    case .assistant:
        print("Turn: Assistant is speaking")
        // Update UI for assistant turn
        // Show assistant indicators
        
    case .none:
        print("Turn: No one speaking")
        // Show neutral state
    }
}
```

---

### `.turnEnded`

**When:** User turn has ended.

**Event Value:** None (no associated data)

**Use Case:** Signal that user input is complete, trigger assistant response, reset turn state.

```swift
echo.when(.turnEnded) { event in
    print("User turn ended")
    // Signal that user input is complete
    // Prepare for assistant response
    // Reset turn indicators
}
```

---

### `.assistantInterrupted`

**When:** Assistant was interrupted (typically by user starting to speak).

**Event Value:** None (no associated data)

**Use Case:** Handle interruption gracefully, stop audio playback, reset assistant state.

```swift
echo.when(.assistantInterrupted) { event in
    print("Assistant was interrupted")
    // Stop audio playback immediately
    // Clear any pending assistant content
    // Reset assistant state
    // Prepare for user input
}
```

---

## Tool Events

### `.toolCallRequested`

**When:** A function/tool call has been requested by the model.

**Event Value:**
- `toolCall: ToolCall` - The tool call details

**ToolCall Structure:**
- `id: String` - Unique identifier for this tool call
- `name: String` - Name of the tool/function to call
- `arguments: SendableJSON` - Arguments for the tool call (can be parsed using `parseArguments()`)

**Use Case:** Intercept tool calls for approval, custom execution logic, logging, or manual handling.

```swift
echo.when(.toolCallRequested) { event in
    guard case .toolCallRequested(let toolCall) = event else { return }
    
    print("Tool call requested:")
    print("  ID: \(toolCall.id)")
    print("  Name: \(toolCall.name)")
    
    // Parse arguments
    do {
        let args = try toolCall.parseArguments()
        print("  Arguments: \(args)")
    } catch {
        print("  Error parsing arguments: \(error)")
    }
    
    // Optionally execute tool manually
    // Or let automatic tool execution handle it
}
```

**Note:** If automatic tool execution is enabled (default), tools execute automatically. Use this event to intercept, log, or override behavior.

---

### `.toolResultSubmitted`

**When:** A tool result has been submitted back to the model.

**Event Value:**
- `toolCallId: String` - The ID of the tool call this result is for
- `result: String` - The tool execution result (typically JSON string)

**Use Case:** Track tool execution, log results, update UI with tool outcomes.

```swift
echo.when(.toolResultSubmitted) { event in
    guard case .toolResultSubmitted(let toolCallId, let result) = event else { return }
    
    print("Tool result submitted:")
    print("  Tool Call ID: \(toolCallId)")
    print("  Result: \(result)")
    
    // Log tool execution
    // Update UI with tool result
    // Track tool usage
}
```

---

## Message Events

### `.messageFinalized`

**When:** A message has been finalized and added to the conversation queue.

**Event Value:**
- `message: Message` - The finalized message

**Message Structure:**
- `id: String` - Unique message identifier
- `role: MessageRole` - Message role (`.user`, `.assistant`, `.system`, `.tool`)
- `text: String` - Text content
- `audioData: Data?` - Optional audio data
- `timestamp: Date` - When message was created
- `sequenceNumber: Int` - Sequence number for ordering
- `content: [MessageContent]?` - Optional rich content array

**Use Case:** Store conversation history, update chat UI, perform message-based actions, maintain conversation state.

```swift
echo.when(.messageFinalized) { event in
    guard case .messageFinalized(let message) = event else { return }
    
    print("Message finalized:")
    print("  ID: \(message.id)")
    print("  Role: \(message.role)")
    print("  Text: \(message.text)")
    print("  Sequence: \(message.sequenceNumber)")
    
    // Store in conversation history
    // Update chat UI
    // Perform message-based actions
    // Maintain conversation state
}
```

---

## Connection Events

### `.connectionStatusChanged`

**When:** WebSocket or HTTP connection status has changed.

**Event Value:**
- `isConnected: Bool` - Whether the connection is currently active

**Use Case:** Handle connection state, show connection status in UI, retry on disconnect, manage offline state.

```swift
echo.when(.connectionStatusChanged) { event in
    guard case .connectionStatusChanged(let isConnected) = event else { return }
    
    if isConnected {
        print("Connected to API")
        // Show connected status
        // Enable features that require connection
    } else {
        print("Disconnected from API")
        // Show disconnected status
        // Disable features that require connection
        // Optionally attempt reconnection
    }
}
```

---

## Mode Events

### `.modeSwitching`

**When:** Mode is in the process of switching (before switch completes).

**Event Value:**
- `from: EchoMode` - The mode switching from (`.audio` or `.text`)
- `to: EchoMode` - The mode switching to (`.audio` or `.text`)

**Use Case:** Show mode transition UI, prepare for mode change, save state before switching.

```swift
echo.when(.modeSwitching) { event in
    guard case .modeSwitching(let from, let to) = event else { return }
    
    print("Switching mode from \(from) to \(to)")
    
    // Show transition UI
    // Save current state
    // Prepare for mode change
    // Disable features from old mode
}
```

---

### `.modeSwitched`

**When:** Mode has successfully switched.

**Event Value:**
- `to: EchoMode` - The new active mode (`.audio` or `.text`)

**Use Case:** Update UI for new mode, enable mode-specific features, initialize mode-specific components.

```swift
echo.when(.modeSwitched) { event in
    guard case .modeSwitched(let to) = event else { return }
    
    print("Mode switched to: \(to)")
    
    switch to {
    case .audio:
        // Enable audio features
        // Show audio controls
        // Initialize audio components
        
    case .text:
        // Enable text features
        // Show text input
        // Initialize text components
    }
}
```

---

## Embedding Events

### `.embeddingGenerated`

**When:** A single embedding has been generated.

**Event Value:**
- `text: String` - The text that was embedded
- `dimensions: Int` - The dimension count of the embedding
- `model: String` - The model used for embedding

**Use Case:** Track embedding generation, log embedding operations, update UI with embedding status.

```swift
echo.when(.embeddingGenerated) { event in
    guard case .embeddingGenerated(let text, let dimensions, let model) = event else { return }
    
    print("Embedding generated:")
    print("  Text: \(text)")
    print("  Dimensions: \(dimensions)")
    print("  Model: \(model)")
    
    // Track embedding generation
    // Log for analytics
    // Update UI
}
```

---

### `.embeddingsGenerated`

**When:** A batch of embeddings has been generated.

**Event Value:**
- `count: Int` - Number of embeddings generated
- `dimensions: Int` - The dimension count of the embeddings
- `model: String` - The model used for embeddings

**Use Case:** Track batch embedding operations, log batch processing, update progress indicators.

```swift
echo.when(.embeddingsGenerated) { event in
    guard case .embeddingsGenerated(let count, let dimensions, let model) = event else { return }
    
    print("Batch embeddings generated:")
    print("  Count: \(count)")
    print("  Dimensions: \(dimensions)")
    print("  Model: \(model)")
    
    // Track batch operation
    // Update progress indicator
    // Log for analytics
}
```

---

## Error Events

### `.error`

**When:** An error occurred during operation.

**Event Value:**
- `error: Error` - The error that occurred

**Use Case:** Handle errors gracefully, show error messages to users, log errors, implement retry logic.

```swift
echo.when(.error) { event in
    guard case .error(let error) = event else { return }
    
    print("Error occurred: \(error.localizedDescription)")
    
    // Show error to user
    // Log error for debugging
    // Implement retry logic if appropriate
    // Update error state in UI
}
```

**Note:** Errors can be of various types (`EchoError`, `RealtimeError`, `ResponsesError`, etc.). Check error type for specific handling.

---

## Advanced Usage Patterns

### Multiple Handlers for Same Event

You can register multiple handlers for the same event type:

```swift
// Handler 1: Logging
echo.when(.userTranscriptionCompleted) { event in
    guard case .userTranscriptionCompleted(let transcript, _) = event else { return }
    print("Transcript: \(transcript)")
}

// Handler 2: UI Update
echo.when(.userTranscriptionCompleted) { event in
    guard case .userTranscriptionCompleted(let transcript, _) = event else { return }
    // Update UI with transcript
}
```

### Listening to Multiple Events

Handle multiple events with a single handler:

```swift
// Handle all speaking events together (variadic syntax)
echo.when(.userStartedSpeaking, .userStoppedSpeaking, 
          .assistantStartedSpeaking, .assistantStoppedSpeaking) { event in
    switch event {
    case .userStartedSpeaking:
        print("🎤 User started speaking")
    case .userStoppedSpeaking:
        print("🎤 User stopped speaking")
    case .assistantStartedSpeaking:
        print("🔊 Assistant started speaking")
    case .assistantStoppedSpeaking:
        print("🔊 Assistant stopped speaking")
    default:
        break
    }
}

// Handle all error-related events
echo.when(.error, .connectionStatusChanged) { event in
    switch event {
    case .error(let error):
        print("Error: \(error)")
    case .connectionStatusChanged(let isConnected):
        if !isConnected {
            print("Connection lost - may need retry")
        }
    default:
        break
    }
}

// Handle all transcription and response events
echo.when(.userTranscriptionCompleted, .assistantResponseDone) { event in
    switch event {
    case .userTranscriptionCompleted(let transcript, _):
        print("User: \(transcript)")
    case .assistantResponseDone(_, let text):
        print("Assistant: \(text)")
    default:
        break
    }
}
```

**Note:** You can also use array syntax if you prefer: `echo.when([.event1, .event2]) { ... }`

### Async Operations in Handlers

Use async handlers for operations that require `await`:

```swift
echo.when(.messageFinalized) { event in
    guard case .messageFinalized(let message) = event else { return }
    
    // Perform async operations
    await saveMessageToDatabase(message)
    await updateRemoteServer(message)
    await sendNotification(message)
}
```

### Pattern Matching Best Practices

Always use pattern matching to extract event values safely:

```swift
// ✅ Good: Pattern matching with guard
echo.when(.userTranscriptionCompleted) { event in
    guard case .userTranscriptionCompleted(let transcript, let itemId) = event else { return }
    // Use transcript and itemId
}

// ❌ Bad: Don't assume event structure
echo.when(.userTranscriptionCompleted) { event in
    // Don't access properties directly - use pattern matching
}
```

### Event Stream Access

You can also access all events via the async stream:

```swift
Task {
    for await event in echo.eventEmitter.events {
        switch event {
        case .userTranscriptionCompleted(let transcript, _):
            print("User said: \(transcript)")
        case .assistantResponseDone(_, let text):
            print("Assistant said: \(text)")
        default:
            break
        }
    }
}
```

---

## Event Flow Examples

### Complete Conversation Flow

```swift
// User starts speaking
echo.when(.userStartedSpeaking) { _ in
    print("🎤 User started speaking")
}

// User stops speaking
echo.when(.userStoppedSpeaking) { _ in
    print("🎤 User stopped speaking")
}

// User audio committed
echo.when(.userAudioBufferCommitted) { event in
    guard case .userAudioBufferCommitted(let itemId) = event else { return }
    print("📝 User audio committed: \(itemId)")
}

// Transcription completes
echo.when(.userTranscriptionCompleted) { event in
    guard case .userTranscriptionCompleted(let transcript, _) = event else { return }
    print("📝 User said: \(transcript)")
}

// Assistant response starts
echo.when(.assistantResponseCreated) { event in
    guard case .assistantResponseCreated(let itemId) = event else { return }
    print("🤖 Assistant response created: \(itemId)")
}

// Assistant starts speaking
echo.when(.assistantStartedSpeaking) { _ in
    print("🔊 Assistant started speaking")
}

// Text chunks stream in
echo.when(.assistantTextDelta) { event in
    guard case .assistantTextDelta(let delta) = event else { return }
    print("📝 Text chunk: \(delta)")
}

// Response completes
echo.when(.assistantResponseDone) { event in
    guard case .assistantResponseDone(let itemId, let text) = event else { return }
    print("✅ Assistant response done: \(text)")
}

// Message finalized
echo.when(.messageFinalized) { event in
    guard case .messageFinalized(let message) = event else { return }
    print("💾 Message finalized: \(message.text)")
}
```

---

## Summary

Echo provides a comprehensive event system covering:

- **User Speech**: 4 events for tracking user input
- **Assistant Response**: 6 events for tracking assistant output
- **Audio**: 2 events for audio level and status
- **Turn Management**: 3 events for conversation flow
- **Tools**: 2 events for function calling
- **Messages**: 1 event for finalized messages
- **Connection**: 1 event for connection status
- **Mode**: 2 events for mode switching
- **Embeddings**: 2 events for embedding operations
- **Errors**: 1 event for error handling

All events can be handled using `echo.when(.eventType) { event in ... }` with pattern matching to extract associated values.

