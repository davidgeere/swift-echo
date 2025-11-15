# Changelog

All notable changes to Echo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- **1.0.0** - Initial release with full feature set

## Versioning

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

[1.0.0]: https://github.com/davidgeere/swift-echo/releases/tag/v1.0.0