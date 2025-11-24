# Changelog

All notable changes to Echo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.2.1]: https://github.com/davidgeere/swift-echo/releases/tag/v1.2.1
[1.2.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.2.0
[1.1.2]: https://github.com/davidgeere/swift-echo/releases/tag/v1.1.2
[1.1.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.1.0
[1.0.3]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.3
[1.0.2]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.2
[1.0.1]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.1
[1.0.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.0