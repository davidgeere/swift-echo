**CRITICAL**: Before doing ANY work in this repository, you MUST read and understand the complete architecture specification:
- **[Echo Architecture Specification](Echo%20-%20A%20Unified%20Swift%20Library%20and%20Architecture%20Document.md)**

This architecture document is the authoritative specification for all design decisions, implementation patterns, file organization, API contracts, and architectural principles. Every task, feature, bug fix, or modification must align with the patterns and principles defined in this document.

## Architecture Document

The architecture document provides a professional software engineering specification with:
- **Clear separation of concerns**: Requirements → Architecture → API → Implementation
- **Professional diagrams**: Clean SVG diagrams for system visualization
- **Formal API specifications**: Contracts with detailed interfaces
- **Comprehensive organization**: 9 major sections with table of contents
- **Complete coverage**: All components, patterns, and standards documented

## Project Overview

Echo is a unified Swift library that integrates OpenAI's Realtime API (WebSocket-based voice) and Responses API (REST/SSE-based text) under a single interface. The architecture specification contains:

### Document Structure
1. **Executive Summary** - 5-minute project overview
2. **Requirements Specification** - What needs to be built
3. **System Architecture** - How the system is organized
4. **Component Specifications** - Detailed component designs
5. **API Specification** - Public API contracts
6. **Implementation Guide** - Development standards
7. **Integration Guide** - How to use Echo
8. **Testing Strategy** - Quality assurance approach
9. **Appendices** - Reference material

## Critical Model Requirements

**STRICT**: Echo supports ONLY these OpenAI models:
- **Realtime API**: `gpt-realtime`, `gpt-realtime-mini`
- **Responses API**: `gpt-5`, `gpt-5-mini`, `gpt-5-nano`
- **Embeddings**: `text-embedding-3-small`, `text-embedding-3-large`, `text-embedding-ada-002`
- **Transcription**: `whisper-1`

Any other models (gpt-4, gpt-3.5, claude, etc.) will throw runtime errors.

## Build and Test Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run specific test
swift test --filter MessageQueueTests

# Build for release
swift build -c release
```

## Workflow for All Tasks

**Before starting any work:**

1. **Read the architecture specification** - Start with Section 1 (Executive Summary)
2. **Navigate to relevant section** - Use the table of contents
3. **Check component specifications** - Section 4 for detailed designs
4. **Review API contracts** - Section 5 for public interfaces
5. **Follow implementation guide** - Section 6 for standards

**Quick Navigation Guide:**
- **For new features** → Section 2 (Requirements) + Section 5 (API)
- **For bug fixes** → Section 4 (Components) + Section 8 (Testing)
- **For architecture** → Section 3 (System Architecture)
- **For usage** → Section 7 (Integration Guide)

## Critical Architectural Components

The architecture specification provides complete implementation details for:

1. **MessageQueue** (Section 3.3, 4.1.3) - Handles out-of-order message sequencing
2. **Conversation** (Section 4.1.2) - Manages unified state and mode switching
3. **RealtimeClient** (Section 4.2.1) - WebSocket client with model validation
4. **ResponsesClient** (Section 4.3.1) - HTTP/SSE client with model validation
5. **EventEmitter** (Section 4.4.1) - Type-safe event system
6. **TurnManager** (Section 4.1.4) - Voice activity detection
7. **Tool System** (Section 4.4.2) - Function calling and MCP

## File Organization Rules

**STRICT**: One type per file, file name must exactly match the type name.

See Section 6.1 (Project Structure) for the complete directory layout:
```
Sources/Echo/
├── Core/         # Message, Conversation, Queue, Turn
├── Realtime/     # WebSocket, audio, VAD
├── Responses/    # REST, SSE, structured output
├── Events/       # Event system
├── Tools/        # Function calling
├── Models/       # Model definitions (STRICT validation)
└── Audio/        # Audio processing
```

## Development Guidelines

### Swift 6.2 Requirements (Section 6.4)
- **async/await** for all asynchronous operations
- **actor** for thread-safe components
- **@Observable** for UI state (NOT ObservableObject)
- **AsyncStream** for streaming data
- **Sendable** for concurrent types

### Forbidden Patterns (Section 6.4.2)
- ❌ GCD (DispatchQueue, DispatchGroup)
- ❌ Combine framework
- ❌ Completion handlers
- ❌ @StateObject, @ObservedObject
- ❌ XCTest (use Swift Testing)

## Testing Requirements

See Section 8 (Testing Strategy) for complete guidelines:
- **TDD mandatory**: Write test first, then implementation
- **Swift Testing**: Use @Test and #expect, not XCTest
- **80% minimum coverage**: All public APIs must have tests
- **Mock objects**: Use protocol-based mocks for isolation

## Key Architecture Insights

### Message Queue (Section 3.3)
The central innovation - ensures proper message ordering even when transcripts arrive after assistant responses in audio mode.

### Mode Switching (Section 3.4)
Seamless context preservation through message queue when switching between audio and text modes.

### Concurrency Model (Section 3.5)
Pure Swift 6 concurrency with actors for isolation and AsyncStream for data flow.

## Visual Architecture

The specification includes professional SVG diagrams:
- **High-level architecture** - System containment and structure
- **Message queue flow** - Sequencing and ordering logic
- **Mode switching** - Transition between audio and text
- **Concurrency model** - Actor isolation and streams
- **Data flow** - End-to-end request processing

## Quick Reference to Specification Sections

| Working On | Read Section |
|------------|-------------|
| Message ordering | 3.3 Central Message Queue |
| Mode switching | 3.4 Mode Switching |
| Model validation | 2.3 Model Requirements |
| Public API | 5. API Specification |
| Components | 4. Component Specifications |
| Testing | 8. Testing Strategy |
| Standards | 6. Implementation Guide |

## ⚠️ Branching Rules

**Read [WORKFLOW.md](https://github.com/davidgeere/samaritan-architecture/blob/main/WORKFLOW.md) for full details.**

| Rule | Command |
|------|---------|
| **Create branches from `staging`** | `git checkout staging && git pull && git checkout -b feature/sam-XXX-desc` |
| **PR to `staging` first** | Test on staging environment before main |
| **PR to `main` only after staging verified** | Never PR directly to main |
| **Keep staging synced** | After any main hotfix: `git checkout staging && git merge main && git push` |

**NEVER:**
- ❌ Create branches from `main`
- ❌ PR directly to `main` (unless promoting from staging)
- ❌ Let `staging` fall behind `main`

---

## Final Reminder

🔴 **ALWAYS CONSULT THE ARCHITECTURE SPECIFICATION** 🔴

The specification at [Echo - A Unified Swift Library and Architecture Document.md](Echo%20-%20A%20Unified%20Swift%20Library%20and%20Architecture%20Document.md) is the authoritative source. It contains:
- Complete working examples
- Detailed component designs
- API contracts
- Testing patterns
- Implementation standards

Your implementation MUST match the patterns and principles documented there.