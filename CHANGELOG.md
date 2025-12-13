# Changelog

All notable changes to Echo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2025-12-12

### Added

#### Correlation-Based Echo Cancellation

A new, more accurate approach to echo cancellation that detects echo by comparing waveform patterns rather than just audio volume. This solves two key problems with volume-based gating:

- **Loud echo (phone near speaker)** - Volume gating allows it through
- **Quiet user speech (phone held away)** - Volume gating blocks it

The correlation-based approach uses cross-correlation to compare microphone input with recently played audio. If the waveforms match (high correlation), it's echo. If they don't match (low correlation), it's genuine user speech.

##### New Components

###### EchoCanceller Actor
```swift
// Create canceller with configuration
let canceller = EchoCanceller(configuration: .default)

// Activate when assistant starts speaking
await canceller.activate()

// Add reference audio (called by AudioPlayback)
await canceller.addReference(pcm16Data: audioData)

// Check if input is echo (called by AudioCapture)
let isEcho = await canceller.isEcho(samples)  // true = suppress, false = forward
```

###### EchoCancellerConfiguration
```swift
EchoCancellerConfiguration(
    enabled: true,
    sampleRate: 24000,
    correlationThreshold: 0.65,  // 0.0-1.0, higher = more selective
    maxReferenceDurationMs: 500, // How much output audio to remember
    minDelayMs: 5,               // Minimum echo delay to search
    maxDelayMs: 100              // Maximum echo delay to search
)

// Presets
EchoCancellerConfiguration.default      // Balanced for most environments
EchoCancellerConfiguration.aggressive   // Lower threshold, longer buffer
EchoCancellerConfiguration.conservative // Higher threshold, fewer false positives
EchoCancellerConfiguration.nearField    // Phone close to face
EchoCancellerConfiguration.farField     // Speakerphone or Bluetooth speaker
```

###### Echo Protection Modes
```swift
enum EchoProtectionMode {
    case threshold    // RMS volume gating (original)
    case correlation  // Waveform pattern matching (new)
    case hybrid       // Both methods (most robust)
}
```

##### Updated Configuration

###### EchoProtectionConfiguration
```swift
// Now supports mode selection and correlation config
EchoProtectionConfiguration(
    enabled: true,
    mode: .hybrid,                          // NEW
    bargeInThreshold: 0.15,
    postSpeechDelay: .milliseconds(300),
    correlationConfig: .default             // NEW
)

// New presets
EchoProtectionConfiguration.correlationDefault  // Pure correlation mode
EchoProtectionConfiguration.hybrid              // Both methods (recommended)
```

###### Updated Presets
- `EchoConfiguration.speakerOptimized` now uses `.hybrid` mode
- `RealtimeClientConfiguration.speakerOptimized` now uses `.hybrid` mode

###### New Presets
- `EchoConfiguration.correlationOptimized` - Pure correlation mode
- `RealtimeClientConfiguration.correlationOptimized` - Pure correlation mode

##### How It Works

```
[Speaker Output] → [Reference Buffer] → [Cross-Correlation]
                                              ↑
[Microphone Input] ──────────────────────────┘
                                              ↓
                                    [Correlation Score]
                                              ↓
                                      > 0.65 = ECHO → Suppress
                                      < 0.65 = USER → Forward
```

1. **Reference Buffer**: Keeps last 500ms of played audio
2. **Delay Search**: Searches 5-100ms delay range for echo
3. **Normalized Correlation**: Computes correlation coefficient (0.0-1.0)
4. **Decision**: High correlation = echo, low correlation = real speech

### Changed

#### Protocol Updates
- `AudioCaptureProtocol`: Added `setEchoCanceller(_:)` method
- `AudioPlaybackProtocol`: Added `setEchoCanceller(_:)` method

#### Configuration Updates
- `EchoProtectionConfiguration`: Added `mode` and `correlationConfig` properties
- Existing threshold-based configurations continue to work unchanged

### Migration

**Backward Compatible**: Existing code using threshold-based echo protection continues to work. The default mode is now `.threshold` for backward compatibility.

**To enable correlation-based echo cancellation:**

```swift
// Option 1: Use speakerOptimized preset (now uses hybrid mode)
let config = EchoConfiguration.speakerOptimized

// Option 2: Use correlationOptimized preset
let config = EchoConfiguration.correlationOptimized

// Option 3: Custom configuration
let config = EchoConfiguration(
    echoProtection: EchoProtectionConfiguration(
        mode: .correlation,
        correlationConfig: .default
    )
)
```

---

## [1.6.1] - 2025-12-10

### Fixed

#### AudioPlayback Switch Statement (#17)
- **Fixed switch not exhaustive error** - Added missing `.smart` case to `setAudioOutput()` method
  - If Bluetooth device is connected → routes to Bluetooth
  - If no Bluetooth → routes to speaker with echo protection
- `.smart` can now be used as `defaultAudioOutput` in `EchoConfiguration`
- `EchoConfiguration.speakerOptimized` preset now works correctly

---

## [1.6.0] - 2025-12-10

### Added

#### Echo Protection for Speaker Mode
Prevents the AI assistant from interrupting itself when using speaker output, while still allowing genuine user barge-in (interruptions). This is a multi-layered solution combining server-side and client-side protections.

##### Server-Side Features
- **Semantic VAD with eagerness control** - Uses meaning-based speech detection instead of just volume
  - `VADConfiguration.Eagerness` enum: `.low`, `.medium`, `.high`
  - Low eagerness waits longer before deciding user finished speaking (filters echo)
  - Semantic VAD understands conversational context, not just audio levels

- **Noise reduction configuration** - Server-side audio filtering
  - `InputAudioConfiguration` with `NoiseReductionType`
  - `.nearField` - For earpiece/receiver mode (close to mic)
  - `.farField` - For speaker mode (better echo handling)

- **VAD response control** - New properties actually sent to API
  - `createResponse: Bool` - Whether to auto-create response when user stops
  - `interruptResponse: Bool` - Whether user can interrupt assistant

##### Client-Side Features
- **Audio gating** - Filters low-level audio during assistant speech
  - `EchoProtectionConfiguration` with `bargeInThreshold` (0.0-1.0)
  - Only audio above threshold passes through when assistant is speaking
  - `postSpeechDelay` - Delay after assistant stops before disabling gate

- **Automatic VAD switching** - Adjusts VAD based on audio output device
  - Speaker → Semantic VAD with low eagerness
  - Earpiece/Headphones → Server VAD with higher sensitivity
  - Bluetooth → Semantic VAD with medium eagerness

##### Smart Audio Output
- **`.smart` case for AudioOutputDeviceType** - Intelligent device selection
  - Uses Bluetooth if connected
  - Falls back to speaker with echo protection
  - Best for voice conversation apps

- **`mayProduceEcho` property** - Identifies echo-prone outputs
  - Returns `true` for speaker, Bluetooth (conservative)
  - Returns `false` for earpiece, wired headphones

#### New Configuration Types

##### VADConfiguration Updates
```swift
VADConfiguration(
    type: .semanticVAD,
    eagerness: .low,        // NEW: Controls response speed
    threshold: 0.7,
    silenceDurationMs: 500,
    prefixPaddingMs: 300,
    interruptResponse: true, // NEW: Actually sent to API now
    createResponse: true     // NEW: Controls auto-response
)
```

##### InputAudioConfiguration (NEW)
```swift
// Server-side noise reduction
let config = InputAudioConfiguration(noiseReductionType: .farField)

// Presets
InputAudioConfiguration.nearField      // For earpiece
InputAudioConfiguration.farField       // For speaker (echo protection)
InputAudioConfiguration.disabled       // No noise reduction
```

##### EchoProtectionConfiguration (NEW)
```swift
// Client-side audio gating
let config = EchoProtectionConfiguration(
    enabled: true,
    bargeInThreshold: 0.15,  // RMS level for barge-in
    postSpeechDelay: .milliseconds(300)
)

// Presets
EchoProtectionConfiguration.default     // Balanced
EchoProtectionConfiguration.aggressive  // High volume environments
EchoProtectionConfiguration.disabled    // For earpiece/headphones
```

#### New Presets

##### VADConfiguration Presets
- `.speakerOptimized` - Semantic VAD with low eagerness
- `.earpiece` - Server VAD with high eagerness
- `.bluetooth` - Semantic VAD with medium eagerness

##### EchoConfiguration Preset
```swift
// Full speaker-optimized setup
let config = EchoConfiguration.speakerOptimized
// Includes: smart audio output, far-field noise reduction,
// echo protection, and speaker-optimized VAD
```

##### RealtimeClientConfiguration Preset
```swift
let config = RealtimeClientConfiguration.speakerOptimized
```

#### Example Usage
```swift
// Simple: Use the speaker-optimized preset
let config = EchoConfiguration.speakerOptimized
let echo = Echo(key: apiKey, configuration: config)
let conversation = try await echo.startConversation(mode: .audio)

// Custom: Fine-tuned echo protection
let config = EchoConfiguration(
    defaultMode: .audio,
    defaultAudioOutput: .smart,
    inputAudioConfiguration: .farField,
    echoProtection: .aggressive,
    turnDetection: .automatic(.speakerOptimized)
)
```

### Fixed
- **VAD `enableInterruption` not sent to API** - Property was defined but never included in `toRealtimeFormat()`. Now properly sent as `interrupt_response`.

### Technical
- New `InputAudioConfiguration.swift` for server-side noise reduction
- New `EchoProtectionConfiguration.swift` for client-side gating
- Updated `VADConfiguration.swift` with proper semantic VAD serialization
- Updated `AudioCapture.swift` with gating support via `OSAllocatedUnfairLock`
- Updated `RealtimeClient.swift` with echo protection logic
- Updated `AudioOutputDeviceType.swift` with `.smart` case
- 31 new tests in `EchoProtectionTests.swift`

---

## [1.5.0] - 2025-12-06

### Added

#### Audio Frequency Analysis
- **FFT-based frequency analysis** - Full frequency band analysis using Accelerate framework
  - `AudioLevels` struct with `level`, `low`, `mid`, `high` properties (all 0.0-1.0)
  - Low band: 20-250Hz (bass, rumble)
  - Mid band: 250-4000Hz (voice, melody)
  - High band: 4000-20000Hz (sibilance, air)

- **Input level monitoring** - Microphone audio levels with frequency bands
  - `conversation.inputLevels` - Observable property on Conversation
  - `.inputLevelsChanged(levels: AudioLevels)` event via echo.events stream
  - Automatic smoothing for UI-friendly level transitions

- **Output level monitoring** - Speaker audio levels with frequency bands
  - `conversation.outputLevels` - Observable property on Conversation
  - `.outputLevelsChanged(levels: AudioLevels)` event via echo.events stream
  - Tap automatically installed on mainMixerNode

#### Example Usage
```swift
// Observable properties on Conversation (SwiftUI-friendly)
conversation.inputLevels.level  // Overall mic level
conversation.inputLevels.low    // Bass frequencies
conversation.inputLevels.mid    // Voice frequencies  
conversation.inputLevels.high   // Treble frequencies

conversation.outputLevels.level // Overall output level
conversation.outputLevels.low   // etc.

// Events via stream
for await event in echo.events {
    switch event {
    case .inputLevelsChanged(let levels):
        updateInputVisualizer(levels)
    case .outputLevelsChanged(let levels):
        updateOutputVisualizer(levels)
    default:
        break
    }
}
```

### Changed

- `audioLevelStream` type changed from `AsyncStream<Double>` to `AsyncStream<AudioLevels>`
- Events now emit `AudioLevels` instead of simple `Double` for richer visualization data

### Deprecated

- `.audioLevelChanged(level: Double)` - Use `.inputLevelsChanged(levels: AudioLevels)` instead

### Technical
- New `FrequencyAnalyzer.swift` using vDSP FFT from Accelerate framework
- New `AudioLevels.swift` struct (Sendable, Equatable)
- Thread-safe level analysis with `OSAllocatedUnfairLock`
- 17 new tests in `FrequencyAnalysisTests.swift`

---

## [1.4.0] - 2025-12-06

### Added

#### Audio Engine Exposure for External Monitoring
- **AVAudioEngine access** - Exposed the internal audio engine for external audio monitoring
  - `AudioPlayback.audioEngine` - Direct access to the underlying AVAudioEngine (read-only)
  - Enables audio visualizations, level metering, and frequency analysis
  - Property is nil when playback is not active

- **Audio tap installation API** - Safe methods for installing audio taps
  - `conversation.installAudioTap(bufferSize:format:handler:)` - Install a tap on the main mixer node
  - `conversation.removeAudioTap()` - Remove an installed tap
  - Handles Swift 6 concurrency safely (AVAudioEngine is not Sendable)

#### Example Usage
```swift
// Install a tap for audio analysis
try await conversation.installAudioTap(bufferSize: 1024) { buffer, time in
    // Process audio buffer for visualization
    let channelData = buffer.floatChannelData?[0]
    let frameLength = Int(buffer.frameLength)
    // Analyze audio data...
}

// Remove tap when done
await conversation.removeAudioTap()
```

#### Protocol Update
- Added `audioEngine: AVAudioEngine? { get }` to `AudioPlaybackProtocol`
- Updated `MockAudioPlayback` to return nil for audioEngine (no real engine in tests)

### Technical
- Used `@preconcurrency import AVFoundation` to handle Swift 6 strict concurrency
- Closure-based API for Conversation/RealtimeClient to avoid Sendable constraints
- New `AudioEngineExposureTests.swift` with 7 comprehensive tests

---

## [1.3.0] - 2025-11-29

### Breaking Changes

#### Event System Overhaul
- **Removed `when()` event handler methods** - All `when()` method overloads have been removed from `Echo` and `EventEmitter`
  - Previously: `echo.when(.userStartedSpeaking) { event in ... }`
  - Now: `for await event in echo.events { ... }` with switch/case pattern matching
  - This change eliminates orphaned Tasks and complex cleanup requirements

- **Removed `EventHandler.swift`** - No longer needed with the pure sink architecture

### Added

#### New Event Observation API
- **AsyncStream-based event observation** - Use `echo.events` to observe all events
  ```swift
  Task {
      for await event in echo.events {
          switch event {
          case .userStartedSpeaking:
              // Handle event
          case .error(let error):
              // Handle error
          default:
              break
          }
      }
  }
  ```

#### Internal Architecture
- **`InternalDelegates.swift`** - New internal protocols for component coordination:
  - `AudioInterruptible` - For components that can interrupt audio
  - `ToolExecuting` - For centralized tool execution
  - `RealtimeClientDelegate` - For RealtimeClient internal events
  - `TurnManagerDelegate` - For TurnManager coordination
  - `ToolHandlerProvider` - For custom tool handler injection

- **`ToolExecutor` actor** - Centralized tool execution:
  - Manages tool registration and execution
  - Supports both automatic and custom tool handlers
  - Thread-safe via actor isolation

- **`toolHandler` property on Echo** - For custom tool handling:
  ```swift
  echo.toolHandler = { toolCall in
      // Custom handling
      return "result"
  }
  ```

### Changed

#### EventEmitter
- Simplified to pure sink pattern (emit-only)
- Only exposes `events: AsyncStream<EchoEvent>` for external observation
- Internal components use direct delegate method calls

#### Internal Coordination
- Components now use delegate patterns instead of event listeners
- Direct method calls for internal coordination (no Tasks)
- Deterministic execution flow

### Fixed

#### Memory Management
- **Eliminated orphaned Task instances** - No more background Tasks for internal event listening
- **Proper AsyncStream cleanup** - All continuations are properly finished in `deinit`
- **No complex cleanup requirements** - Components manage their own lifecycle

### Migration Guide

**Before (1.2.x):**
```swift
// Single event
echo.when(.userStartedSpeaking) { event in
    print("User started speaking")
}

// Multiple events
echo.when(.userStartedSpeaking, .userStoppedSpeaking) { event in
    // Handle events
}
```

**After (1.3.0):**
```swift
// All events via stream
Task {
    for await event in echo.events {
        switch event {
        case .userStartedSpeaking:
            print("User started speaking")
        case .userStoppedSpeaking:
            print("User stopped speaking")
        default:
            break
        }
    }
}
```

## [1.2.2] - 2025-11-23

### Fixed

#### Audio Output Device Routing
- **Fixed audio routing to speaker/receiver** - Audio now correctly routes to the selected output device
  - Previously, audio would continue playing from receiver even when speaker was selected
  - Both capture and playback engines are now properly stopped before route changes
  - Route changes are verified and engines restart with the new route
  - Prevents route caching issues that caused incorrect audio output

- **Improved engine restart sequence** - Better timing and verification during audio output changes
  - Engines stop before route change to prevent route caching
  - Added delays to allow route changes to stabilize
  - Route verification ensures the change actually took effect
  - Retry logic for speaker override if route doesn't change immediately
  - Both engines restart reliably after route change

- **Fixed AudioCapture.pause() method** - Corrected implementation to properly stop engine
  - AVAudioEngine doesn't have a pause() method
  - Now properly stops engine while keeping tap installed for resume()
  - Allows clean engine restart without reinstalling audio tap

### Added

#### Documentation
- **Background audio support documentation** - Added README section explaining app-level configuration
  - Documents required `UIBackgroundModes` entry in Info.plist
  - Notes that library already supports background audio with current setup

## [1.2.1] - 2025-11-23

### Fixed

#### Audio Output Device Switching
- **Fixed capture engine stopping after audio output change** - Capture engine now automatically restarts when it stops after switching audio output devices
  - Previously, switching from receiver to speaker would stop the capture engine, causing the model to stop responding
  - Capture engine is now automatically detected and restarted after audio output changes
  - Prevents loss of listening ability when switching audio devices

- **Fixed playback engine restart failures** - Improved playback engine restart logic with better error handling
  - Added proper engine stop/start sequence with delays to ensure clean restart
  - Better error handling and logging for engine restart failures
  - Prevents playback from stopping when switching audio devices

- **Improved audio session management** - Better handling of audio session reconfiguration
  - Attempts to avoid deactivating session when possible to preserve engine state
  - Uses `.notifyOthersOnDeactivation` option when deactivation is necessary
  - Remembers engine state before changes and restores it after reconfiguration

### Added

#### Debug Logging
- **Comprehensive debug logging for audio diagnostics** - Added extensive debug logging (within `#if DEBUG` blocks) to help diagnose audio issues
  - Logs engine running state before and after audio output changes
  - Logs capture and playback active states during device switching
  - Logs audio session route changes and reconfiguration steps
  - Logs engine restart attempts and success/failure
  - Logs transcription events and VAD detection
  - Logs mode switching transitions between audio and text
  - All debug logs are conditional and only active in DEBUG builds

## [1.2.0] - 2025-11-23

### Changed

#### Audio Output Device Selection API
- **Replaced speaker routing API** - New device-based audio output selection system
  - Removed `setSpeakerRouting(useSpeaker: Bool)` method
  - Removed `speakerRouting: Bool?` property
  - Removed `isBluetoothConnected: Bool` property
  - Added `setAudioOutput(device: AudioOutputDeviceType)` method for device selection
  - More intuitive and flexible API for controlling audio output

### Added

#### Audio Output Device Types
- **AudioOutputDeviceType enum** - Comprehensive device type system
  - `.builtInSpeaker` - Force built-in speaker output
  - `.builtInReceiver` - Force earpiece/receiver output
  - `.bluetooth(name: String?)` - Bluetooth audio device (with optional device name)
  - `.wiredHeadphones(name: String?)` - Wired headphones (with optional device name)
  - `.systemDefault` - Let system choose the default route
  - Includes `description` property for UI display
  - Includes `isBluetooth` computed property

#### Audio Output State Management
- **Available devices list** - Query all available audio output devices
  - `conversation.availableAudioOutputDevices` - Returns array of all connected devices
  - Includes device names when available (e.g., "AirPods Pro", "External Speaker")
  - Always includes built-in speaker and receiver
  - Lists all connected Bluetooth devices by name

- **Current output tracking** - Check active audio output device
  - `conversation.currentAudioOutput` - Returns currently active output device
  - Updates automatically when user switches devices in system
  - Includes device name when available

#### Audio Output Change Events
- **audioOutputChanged event** - Emitted when audio output device changes
  - `.audioOutputChanged(device: AudioOutputDeviceType)` - Fired when output changes
  - Emitted when `setAudioOutput()` is called programmatically
  - Emitted when user switches device via system controls
  - Allows UI to update in real-time when output changes

### Technical
- Created `AudioOutputDeviceType.swift` enum with device type definitions
- Updated `AudioPlayback` to implement new device-based API
- Updated `AudioPlaybackProtocol` with new methods and properties
- Updated `RealtimeClient` to delegate to playback and emit events
- Updated `Conversation` to expose new API with mode validation
- Updated `MockAudioPlayback` for testing
- Added route change observer in `RealtimeClient` for automatic event emission
- Added comprehensive test coverage (13 new tests in `AudioOutputDeviceTests.swift`)

## [1.1.2] - 2025-11-23

### Fixed

#### Audio Routing
- **Fixed speaker routing not working** - Speaker routing now properly routes to built-in speaker when `setSpeakerRouting(useSpeaker: true)` is called
  - Fixed issue where `.voiceChat` mode was preventing speaker override from working
  - Now uses `.defaultToSpeaker` category option combined with `overrideOutputAudioPort()` for reliable speaker routing
  - Prevents connection drops when toggling speaker routing

### Added

#### Audio State Tracking
- **Speaker routing state property** - Check current speaker routing state
  - `conversation.speakerRouting` - Returns `true` if speaker is forced, `false` if using default routing, `nil` if not set
  - Allows UI to display current audio output routing state

- **Bluetooth connection detection** - Detect if Bluetooth audio device is connected
  - `conversation.isBluetoothConnected` - Returns `true` if Bluetooth audio device is connected
  - Supports HFP, A2DP, and Bluetooth LE audio devices
  - Useful for showing Bluetooth connection status in UI

### Technical
- Updated `AudioPlayback.setSpeakerRouting()` to properly configure audio session with `.defaultToSpeaker` option
- Added `speakerRouting` property to `AudioPlaybackProtocol`, `AudioPlayback`, `RealtimeClient`, and `Conversation`
- Added `isBluetoothConnected` property to `AudioPlaybackProtocol`, `AudioPlayback`, `RealtimeClient`, and `Conversation`
- Updated `MockAudioPlayback` to implement new properties for testing
- Removed disruptive `setActive()` call that was causing connection drops

## [1.1.0] - 2025-11-23

### Added

#### All Events Handler
- **Listen to all events** - New handler pattern for listening to every event emitted by Echo
  - `echo.when { event in ... }` - Non-async handler (fire-and-forget, returns immediately)
  - `await echo.when { event in ... }` - Async handler (returns handler IDs for removal)
  - Handlers automatically registered for all event types
  - Useful for logging, analytics, or global event monitoring

#### Events Stream
- **Async stream for all events** - Sequential event processing with `for await` loop
  - `for await event in echo.events { ... }` - Process events sequentially
  - Can break out of loop when done processing
  - Useful for state machines or sequential event processing
  - Each event processed completely before next one arrives

### Changed
- **Memory safety improvements** - Event handlers are now automatically cleaned up when Echo is deallocated
  - Added `handlers.removeAll()` in `EventEmitter.deinit` to prevent memory leaks
  - Prevents retain cycles from handler closures

### Technical
- Added 4 new `when()` overloads for all-events handling (sync/async variants)
- Added `events` property exposing `AsyncStream<EchoEvent>` for sequential processing
- Updated `EventEmitter.deinit` to clear handlers on deallocation
- Added comprehensive test coverage (5 new tests) for all-events functionality

## [1.0.3] - 2025-01-27

### Added

#### Audio Lifecycle Events
- **Audio lifecycle event tracking** - New events for tracking audio system startup and shutdown
  - `.audioStarting` - Emitted when audio setup begins (before capture/playback initialization)
  - `.audioStarted` - Emitted when audio capture and playback are fully ready
  - `.audioStopped` - Emitted when audio stops or fails during setup
  - Allows UI to show progress states during conversation startup (e.g., "Connecting audio...", "Ready to speak")
  - Distinct from `connectionStatusChanged` (network connection) and `muted` state (runtime control)
  - Events are emitted in sequence: `audioStarting` → `audioStarted` → `audioStopped`

#### Testing
- **Audio lifecycle event tests** - Comprehensive test coverage for new events
  - 6 tests covering all audio lifecycle scenarios
  - Tests for successful startup sequence
  - Tests for failure scenarios
  - Tests for explicit stop behavior
  - Tests for edge cases (stopping without starting)

### Technical
- Added `audioStarting`, `audioStarted`, `audioStopped` to `EventType` enum
- Added corresponding cases to `EchoEvent` enum with type mapping
- Updated `RealtimeClient.startAudio()` to emit lifecycle events
- Updated `RealtimeClient.stopAudio()` to emit `audioStopped` when appropriate
- Updated `EVENTS.md` with documentation and examples for new events

## [1.0.2] - 2025-11-23

### Added

#### Event System Enhancements
- **Multiple event listeners** - Listen to multiple events with a single handler
  - Array syntax: `echo.when([.event1, .event2]) { event in ... }`
  - Variadic syntax: `echo.when(.event1, .event2) { event in ... }`
  - Both syntaxes are equivalent and fully supported
  - Reduces code duplication when handling multiple events the same way

#### Documentation
- **EVENTS.md** - Comprehensive event reference guide
  - Complete documentation for all 25 event types
  - Examples showing how to use each event
  - Pattern matching examples for extracting event values
  - Advanced usage patterns and best practices
  - Event flow examples for complete conversations

#### Testing
- **Event system test suite** - Comprehensive test coverage
  - 18 tests covering all event functionality
  - Tests for single event handlers (sync and async)
  - Tests for multiple events (array and variadic syntax)
  - Tests for event value extraction
  - Tests for handler removal and management
  - Tests for Echo.when() integration

### Technical
- Added `when(_ eventTypes: [EventType], handler:)` overloads to `EventEmitter`
- Added `when(_ eventTypes: EventType..., handler:)` variadic overloads to `EventEmitter`
- Added matching public methods to `Echo` class
- All handlers are thread-safe and properly isolated

## [1.0.1] - 2025-11-23

### Added

#### Audio Features
- **Dynamic speaker routing** - Runtime control of audio output routing
  - `conversation.setSpeakerRouting(useSpeaker: Bool)` method to switch between speaker and earpiece
  - When `useSpeaker: true`, forces audio to built-in speaker (bypasses Bluetooth)
  - When `useSpeaker: false`, allows system to choose route (uses Bluetooth if connected, otherwise earpiece)
  - Can be changed at any time during an active conversation
  - Follows the same pattern as `setMuted()` for consistency

### Technical
- Added `setSpeakerRouting()` method to `AudioPlaybackProtocol`, `AudioPlayback`, `RealtimeClient`, and `Conversation`
- Uses `AVAudioSession.overrideOutputAudioPort()` for runtime routing changes
- Properly handles Bluetooth device routing (respects `.allowBluetoothHFP` option)

## [1.0.0] - 2024-11-15

### 🎉 Initial Release

Echo is a unified Swift library for OpenAI's Realtime API (WebSocket-based voice) and Chat API, providing seamless integration between voice and text conversations.

### Added

#### Core Features
- **Unified API** for both Realtime (voice) and Responses (text) APIs
- **Seamless mode switching** between voice and text while preserving context
- **Message queue architecture** ensuring proper message ordering even with out-of-order transcripts
- **Event-driven system** with expressive `echo.when()` syntax for reactive patterns
- **Professional architecture specification** with comprehensive documentation

#### Voice Features (Realtime API)
- Real-time voice conversations with WebSocket connection
- Voice Activity Detection (VAD) with automatic, manual, and disabled modes
- Audio level monitoring for UI animations
- Automatic transcription of all voice interactions
- Support for multiple voices (alloy, ash, ballad, coral, sage, verse)
- Interruption handling and turn management

#### Text Features (Responses API)
- Traditional text-based conversations with streaming support
- Server-Sent Events (SSE) for real-time text streaming
- Full conversation context preservation

#### Embeddings API
- Single and batch embedding generation
- Semantic similarity search
- Support for multiple embedding models:
  - `text-embedding-3-small` (1536 dimensions)
  - `text-embedding-3-large` (3072 dimensions)
  - `text-embedding-ada-002` (legacy)
- Custom dimension support for optimization

#### Structured Output
- Type-safe JSON generation with Codable schemas
- Complex nested structure support
- Automatic validation and type safety

#### Tool Calling
- Function calling support for both APIs
- Automatic tool execution
- Model Context Protocol (MCP) support
- Unified tool interface across voice and text modes

#### Models Support (STRICT)
- **Realtime API**: `gpt-realtime`, `gpt-realtime-mini`
- **Responses API**: `gpt-5`, `gpt-5-mini`, `gpt-5-nano`
- **Embeddings**: Multiple models with dimension control
- **Transcription**: `whisper-1` for speech-to-text

### Technical Implementation
- **Swift 6.0** with strict concurrency checking
- **Actor-based** architecture for thread safety
- **AsyncStream** for message and event delivery
- **@Observable** for SwiftUI integration
- **Native iOS/macOS** support (iOS 18+, macOS 14+)
- **Zero GCD/Combine** - pure Swift concurrency
- **Test-Driven Development** with Swift Testing framework

### Documentation
- Comprehensive architecture specification (1100+ lines)
- Professional SVG architecture diagrams
- API reference with examples
- Integration guide with SwiftUI examples
- Testing strategy and patterns

### Dependencies
- `AsyncHTTPClient` for REST/SSE communication
- `AsyncAlgorithms` for stream operations
- AVFoundation for native audio processing
- URLSession for WebSocket connections

---

## Version History

- **1.7.0** - Correlation-based echo cancellation
- **1.6.1** - Fix: Add missing .smart case to AudioPlayback
- **1.6.0** - Echo protection for speaker mode
- **1.5.0** - Audio frequency analysis and level monitoring
- **1.4.0** - Audio engine exposure for external monitoring (Issue #8)
- **1.3.0** - Architecture refactor: Event decoupling
- **1.2.2** - Audio routing fixes
- **1.2.1** - Fixed capture/playback engine restart after audio output change
- **1.2.0** - Audio output device selection API (breaking changes)
- **1.1.2** - Fixed speaker routing and added state tracking
- **1.1.0** - All events handler and stream
- **1.0.3** - Audio lifecycle events
- **1.0.2** - Multiple event listeners
- **1.0.1** - Added dynamic speaker routing control
- **1.0.0** - Initial release with full feature set

## Versioning

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

[1.7.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.7.0
[1.6.1]: https://github.com/davidgeere/swift-echo/releases/tag/v1.6.1
[1.6.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.6.0
[1.5.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.5.0
[1.4.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.4.0
[1.3.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.3.0
[1.2.2]: https://github.com/davidgeere/swift-echo/releases/tag/v1.2.2
[1.2.1]: https://github.com/davidgeere/swift-echo/releases/tag/v1.2.1
[1.2.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.2.0
[1.1.2]: https://github.com/davidgeere/swift-echo/releases/tag/v1.1.2
[1.1.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.1.0
[1.0.3]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.3
[1.0.2]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.2
[1.0.1]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.1
[1.0.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.0