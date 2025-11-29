# Swift-Echo Architecture Refactor: Event Decoupling

## Document Version
- **Version:** 1.0
- **Date:** 2025-11-29
- **Status:** Proposed

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current Architecture Analysis](#2-current-architecture-analysis)
3. [Target Architecture](#3-target-architecture)
4. [Component Changes](#4-component-changes)
5. [Execution Plan](#5-execution-plan)
6. [Test Strategy](#6-test-strategy)
7. [Migration Guide](#7-migration-guide)
8. [Risk Assessment](#8-risk-assessment)

---

## 1. Executive Summary

### 1.1 Problem Statement

The current EventEmitter serves dual purposes—external notifications and internal coordination—creating tightly coupled components that spawn long-lived Tasks to listen for events. This causes:

- Orphaned Tasks that run indefinitely
- Memory leaks on connect/disconnect cycles
- Resource exhaustion over time
- Complex cleanup requirements that are easily missed

### 1.2 Solution

Decouple internal coordination from external notifications:

| Concern | Current | Proposed |
|---------|---------|----------|
| Internal coordination | Event-based (async, Task listeners) | Direct method calls (sync, no Tasks) |
| External notifications | Same EventEmitter | Pure sink (fire-and-forget) |
| Component coupling | Loose via events | Tight via direct references |
| Task lifetime | Unbounded | None for internal coordination |

### 1.3 Outcomes

- Zero orphaned Tasks from internal event listeners
- Trivial cleanup (no listener Tasks to cancel)
- Clearer control flow (direct calls, not event chains)
- EventEmitter becomes simple and predictable
- All existing functionality preserved

---

## 2. Current Architecture Analysis

### 2.1 Current Event Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CURRENT ARCHITECTURE                               │
│                                                                              │
│  ┌──────────────┐         ┌──────────────┐         ┌──────────────┐        │
│  │ RealtimeClient│◄───────│ EventEmitter │◄────────│  TurnManager │        │
│  │              │────────►│              │────────►│              │        │
│  └──────┬───────┘         └──────┬───────┘         └──────────────┘        │
│         │                        │                                          │
│         │ Task{} listening       │ Task{} listening                        │
│         │ for events             │ for events                               │
│         │                        │                                          │
│  ┌──────▼───────┐         ┌──────▼───────┐                                 │
│  │ AudioPlayback│         │    Echo      │                                 │
│  │              │         │ (tool exec)  │                                 │
│  └──────────────┘         └──────────────┘                                 │
│                                                                              │
│  Problems:                                                                   │
│  - Circular event flow                                                       │
│  - Tasks waiting on AsyncStreams forever                                    │
│  - No clean cancellation path                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Problematic Patterns Identified

#### Pattern 1: Internal Event Listeners in Constructors

**File:** `RealtimeClient.swift:78-91`
```swift
// PROBLEM: Task lives forever, no cancellation
Task {
    await eventEmitter.when(.assistantInterrupted) { [weak self] _ in
        await self?.stopAudioPlayback()
    }
}
```

#### Pattern 2: Event Chain Dependencies

**Flow:** Tool Execution
```
WebSocket receives tool call
    → RealtimeClient.emit(.toolCallRequested)
    → Echo's Task catches event, executes tool
    → Echo.emit(.toolResultSubmitted)
    → RealtimeClient's Task catches event
    → RealtimeClient sends to OpenAI
```
Four components, two orphan-prone Tasks, circular dependency.

#### Pattern 3: Cross-Component Coordination via Events

**Flow:** User Interruption
```
VAD detects speech
    → RealtimeClient.emit(.inputAudioBufferSpeechStarted)
    → TurnManager (if wired) emits .assistantInterrupted
    → RealtimeClient's Task catches, calls audioPlayback.interrupt()
```

### 2.3 Files with Internal Event Listeners

| File | Lines | Issue |
|------|-------|-------|
| `RealtimeClient.swift` | 78-91 | 2 Tasks listening for `.assistantInterrupted`, `.toolResultSubmitted` |
| `RealtimeClient.swift` | 255-260 | Task iterating `audioLevelStream` |
| `RealtimeClient.swift` | 492-497 | Task iterating `messageStream` |
| `RealtimeClient.swift` | 500-509 | Task iterating `connectionStateStream` |
| `RealtimeClient.swift` | 675-695 | NotificationCenter observer (never removed) |
| `Echo.swift` | 60-99 | Task listening for `.toolCallRequested` |
| `Conversation.swift` | 806-856 | 4 Tasks listening for message events |

---

## 3. Target Architecture

### 3.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TARGET ARCHITECTURE                                │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    INTERNAL MACHINERY                                │   │
│  │                    (Direct References, Synchronous Calls)            │   │
│  │                                                                      │   │
│  │   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐     │   │
│  │   │   Realtime   │─────►│    Audio     │      │     Tool     │     │   │
│  │   │    Client    │─────►│  Subsystem   │      │   Executor   │     │   │
│  │   │              │◄─────│              │      │              │     │   │
│  │   └──────┬───────┘      └──────────────┘      └──────▲───────┘     │   │
│  │          │                                           │              │   │
│  │          │ owns/calls directly                       │              │   │
│  │          ▼                                           │              │   │
│  │   ┌──────────────┐                                   │              │   │
│  │   │    Turn      │───────────────────────────────────┘              │   │
│  │   │   Manager    │  (calls toolExecutor.execute() directly)         │   │
│  │   └──────────────┘                                                  │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    │ emit() - fire and forget              │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     EVENT EMITTER (Pure Sink)                        │   │
│  │                                                                      │   │
│  │   • Only receives events via emit()                                 │   │
│  │   • No internal subscribers                                          │   │
│  │   • Just yields to continuation                                      │   │
│  │   • Zero Tasks spawned                                               │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    │ AsyncStream<EchoEvent>                │
└────────────────────────────────────│────────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SDK USER                                        │
│                                                                              │
│   for await event in echo.events {                                          │
│       // Observe and react (UI updates, logging, analytics)                 │
│       // Cannot intercept or modify internal flow                           │
│   }                                                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Core Principles

1. **Events are observations, not commands**
   - Events notify what happened, not what should happen
   - SDK users observe; they don't participate in control flow

2. **Internal coordination is direct**
   - Components hold references to collaborators
   - Method calls, not event emissions
   - Synchronous where possible, async only when necessary

3. **EventEmitter is a pure sink**
   - `emit()` does `continuation.yield()` and returns immediately
   - No internal listeners
   - No Tasks spawned by the library for event handling

4. **Cleanup is trivial**
   - No listener Tasks to track or cancel
   - Components just stop emitting when done

### 3.3 New Internal Protocols

```swift
/// Protocol for components that need audio interrupt capability
protocol AudioInterruptible: AnyObject {
    func interrupt() async
}

/// Protocol for tool execution
protocol ToolExecuting: AnyObject {
    func execute(toolCall: ToolCall) async -> ToolResult
}

/// Delegate for RealtimeClient internal events
protocol RealtimeClientDelegate: AnyObject, Sendable {
    func realtimeClient(_ client: RealtimeClient, didReceiveToolCall call: ToolCall) async
    func realtimeClientDidDetectUserSpeech(_ client: RealtimeClient) async
    func realtimeClientDidDetectUserSilence(_ client: RealtimeClient) async
    func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async
    func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async
}
```

---

## 4. Component Changes

### 4.1 EventEmitter

**File:** `Sources/Echo/Events/EventEmitter.swift`

**Changes:**
- Remove all `when()` handler registration methods
- Remove `handlers` dictionary
- Remove `EventHandler` usage
- Keep only `emit()` and `events` stream
- Simplify to pure sink

**New Structure:**
```
EventEmitter (actor)
├── events: AsyncStream<EchoEvent>        // Public stream for SDK users
├── eventContinuation: Continuation       // Internal
├── emit(_ event: EchoEvent)              // Fire-and-forget
└── deinit                                // Finish continuation
```

**Removed:**
- `when(_:handler:)` - all overloads
- `when(_:asyncHandler:)` - all overloads
- `removeHandler(_:)`
- `removeAllHandlers(for:)`
- `removeAllHandlers()`
- `handlerCount(for:)`
- `totalHandlerCount()`
- `registeredEventTypes()`
- `handlers` dictionary
- All handler execution logic

### 4.2 RealtimeClient

**File:** `Sources/Echo/Realtime/RealtimeClient.swift`

**Changes:**

| Current | New |
|---------|-----|
| Spawns Task to listen for `.assistantInterrupted` | Receives direct call from owner |
| Spawns Task to listen for `.toolResultSubmitted` | Receives direct call via `submitToolResult()` |
| Spawns Task to iterate `messageStream` | Inline processing in receive loop |
| Spawns Task to iterate `connectionStateStream` | Direct state management |
| Spawns Task to iterate `audioLevelStream` | Callback-based or direct delegation |
| NotificationCenter observer (leaked) | Stored observer token, removed on cleanup |

**New Properties:**
```swift
// Direct references instead of event listeners
private weak var delegate: RealtimeClientDelegate?
private var toolExecutor: ToolExecuting?

// Stored for cleanup
private var routeChangeObserver: NSObjectProtocol?
```

**New Methods:**
```swift
/// Called by owner when tool result is ready
func submitToolResult(callId: String, output: String) async

/// Called by owner to interrupt playback
func interruptPlayback() async
```

**Removed from init:**
- All `Task { await eventEmitter.when(...) }` blocks

### 4.3 Conversation

**File:** `Sources/Echo/Core/Conversation.swift`

**Changes:**

| Current | New |
|---------|-----|
| Sets up 4 Task listeners for message queue events | Implements `RealtimeClientDelegate` |
| Receives message events via EventEmitter | Receives direct delegate calls |
| Coordinates via events | Coordinates via direct calls |

**New Implementation:**
```swift
extension Conversation: RealtimeClientDelegate {
    func realtimeClient(_ client: RealtimeClient, didReceiveTranscript transcript: String, itemId: String) async {
        await messageQueue.updateTranscript(id: itemId, transcript: transcript)
        await eventEmitter.emit(.userTranscriptionCompleted(transcript: transcript, itemId: itemId))
    }

    func realtimeClient(_ client: RealtimeClient, didReceiveAssistantResponse text: String, itemId: String) async {
        await messageQueue.updateTranscript(id: itemId, transcript: text)
        await eventEmitter.emit(.assistantResponseDone(itemId: itemId, text: text))
    }

    // ... etc
}
```

**Removed:**
- `setupAudioModeEventListeners()` method
- All internal event listener Tasks

### 4.4 Echo (Main Entry Point)

**File:** `Sources/Echo/Echo.swift`

**Changes:**

| Current | New |
|---------|-----|
| `setupAutomaticToolExecution()` spawns listener Task | ToolExecutor injected into RealtimeClient |
| `when()` methods for handler registration | Removed (SDK users use `events` stream) |
| `when(call:)` for manual tool handling | `toolHandler` closure property |

**New Structure:**
```swift
public class Echo {
    public let configuration: EchoConfiguration
    public var events: AsyncStream<EchoEvent> { eventEmitter.events }

    /// Optional custom tool handler. If nil, tools execute automatically.
    /// If set, this is called instead of automatic execution.
    public var toolHandler: ((ToolCall) async throws -> String)?

    // Internal
    internal let eventEmitter: EventEmitter
    private let toolExecutor: ToolExecutor
}
```

**Removed:**
- All `when()` method overloads
- `setupAutomaticToolExecution()` Task

### 4.5 New Component: ToolExecutor

**File:** `Sources/Echo/Tools/ToolExecutor.swift` (new file)

**Purpose:** Centralized tool execution, called directly by RealtimeClient

```swift
actor ToolExecutor: ToolExecuting {
    private var tools: [String: Tool] = [:]
    private weak var customHandler: ToolHandlerProvider?

    func register(_ tool: Tool)
    func execute(toolCall: ToolCall) async -> ToolResult
}

protocol ToolHandlerProvider: AnyObject {
    var toolHandler: ((ToolCall) async throws -> String)? { get }
}
```

### 4.6 TurnManager

**File:** `Sources/Echo/Core/TurnManager.swift`

**Changes:**
- Remove event emissions for internal state changes
- Add delegate pattern for notifying owner
- Keep public event emissions as side-effects only

**New Properties:**
```swift
protocol TurnManagerDelegate: AnyObject {
    func turnManagerDidRequestInterruption(_ manager: TurnManager) async
}

private weak var delegate: TurnManagerDelegate?
```

**Flow Change:**
```
Before: handleUserStartedSpeaking() → emit(.assistantInterrupted) → Task catches → calls interrupt()
After:  handleUserStartedSpeaking() → delegate?.turnManagerDidRequestInterruption() → direct call
        + emit(.userStartedSpeaking) as side-effect notification
```

### 4.7 AudioCapture / AudioPlayback

**Files:** `Sources/Echo/Audio/AudioCapture.swift`, `AudioPlayback.swift`

**Changes:**
- Keep current functionality
- Audio level reporting via callback instead of AsyncStream iteration by RealtimeClient

**AudioCapture New Pattern:**
```swift
public func start(
    onAudioChunk: @escaping @Sendable (String) async -> Void,
    onAudioLevel: @escaping @Sendable (Double) -> Void  // NEW: Direct callback
) async throws
```

This eliminates the need for RealtimeClient to spawn a Task iterating `audioLevelStream`.

### 4.8 WebSocketManager

**File:** `Sources/Echo/Network/WebSocketManager.swift`

**Changes:**
- Keep `messageStream` and `connectionStateStream` as public AsyncStreams
- But provide callback-based alternatives for internal use

**New Pattern:**
```swift
/// Callback-based message handling (no external Task needed)
func startReceiving(
    onMessage: @escaping @Sendable (String) async -> Void,
    onDisconnect: @escaping @Sendable () async -> Void
) async
```

The owner calls `startReceiving()` and the WebSocketManager runs its own internal receive loop, calling back directly. No external Task iterating a stream.

### 4.9 MessageQueue

**File:** `Sources/Echo/Core/MessageQueue.swift`

**Changes:**
- Add `deinit` to finish all continuations
- Keep subscription model for SDK users via `messages` stream

```swift
deinit {
    for (_, continuation) in continuations {
        continuation.finish()
    }
}
```

### 4.10 Files to Delete

| File | Reason |
|------|--------|
| `Sources/Echo/Events/EventHandler.swift` | No longer needed (no internal handlers) |

### 4.11 Summary of File Changes

| File | Change Type | Scope |
|------|-------------|-------|
| `EventEmitter.swift` | Major refactor | Remove handler system |
| `EventHandler.swift` | Delete | No longer needed |
| `RealtimeClient.swift` | Major refactor | Delegate pattern, remove listener Tasks |
| `Conversation.swift` | Major refactor | Implement delegate, remove listener Tasks |
| `Echo.swift` | Major refactor | Remove `when()` methods |
| `TurnManager.swift` | Moderate refactor | Add delegate pattern |
| `AudioCapture.swift` | Minor refactor | Callback for audio levels |
| `WebSocketManager.swift` | Moderate refactor | Callback-based receiving option |
| `MessageQueue.swift` | Minor fix | Add deinit |
| `ToolExecutor.swift` | New file | Centralized tool execution |
| `HTTPClient.swift` | No change | - |
| `ResponsesClient.swift` | Minor | Review event emissions |

---

## 5. Execution Plan

### Phase 1: Foundation (Non-Breaking Internal Changes)

**Goal:** Establish new patterns without breaking existing API

#### Step 1.1: Create ToolExecutor
- Create `Sources/Echo/Tools/ToolExecutor.swift`
- Implement `ToolExecuting` protocol
- Add unit tests for ToolExecutor

#### Step 1.2: Create Internal Protocols
- Create `Sources/Echo/Protocols/InternalDelegates.swift`
- Define `RealtimeClientDelegate`, `TurnManagerDelegate`
- Define `AudioInterruptible`, `ToolExecuting`

#### Step 1.3: Add Callback Patterns to Audio Components
- Add `onAudioLevel` callback parameter to `AudioCapture.start()`
- Keep existing `audioLevelStream` for backward compatibility (temporarily)
- Add tests for callback pattern

#### Step 1.4: Add Callback Pattern to WebSocketManager
- Add `startReceiving(onMessage:onDisconnect:)` method
- Keep existing streams for backward compatibility (temporarily)
- Add tests for callback pattern

### Phase 2: Internal Rewiring

**Goal:** Switch internal coordination to direct calls

#### Step 2.1: Refactor RealtimeClient
1. Add `delegate` property
2. Add `toolExecutor` property
3. Replace event listener Tasks with delegate calls
4. Wire audio level via callback
5. Wire WebSocket messages via callback
6. Store and cleanup NotificationCenter observer
7. Update unit tests

#### Step 2.2: Refactor TurnManager
1. Add `delegate` property
2. Replace internal event emissions with delegate calls
3. Keep public event emissions as side-effects
4. Add deinit to cancel timer Task
5. Update unit tests

#### Step 2.3: Refactor Conversation
1. Implement `RealtimeClientDelegate`
2. Remove `setupAudioModeEventListeners()`
3. Wire delegate in `initializeAudioMode()`
4. Update unit tests

#### Step 2.4: Refactor Echo
1. Create and own ToolExecutor
2. Implement `ToolHandlerProvider`
3. Inject ToolExecutor into Conversation/RealtimeClient
4. Remove `setupAutomaticToolExecution()` Task
5. Update unit tests

### Phase 3: API Surface Changes (Breaking)

**Goal:** Simplify public API, remove event handler registration

#### Step 3.1: Simplify EventEmitter
1. Remove all `when()` methods
2. Remove `handlers` dictionary
3. Remove handler execution logic
4. Keep only `emit()` and `events`
5. Delete `EventHandler.swift`
6. Update all tests

#### Step 3.2: Update Echo Public API
1. Remove all `when()` method overloads
2. Add `toolHandler` property for custom tool handling
3. Ensure `events` stream is the only observation mechanism
4. Update documentation
5. Update all tests

#### Step 3.3: Cleanup Deprecated Patterns
1. Remove temporary backward-compatible code from Phase 1
2. Remove `audioLevelStream` Task iteration option
3. Remove stream-based WebSocket iteration option
4. Final test pass

### Phase 4: Validation

#### Step 4.1: Resource Leak Testing
1. Create stress test: repeated connect/disconnect cycles
2. Monitor memory with Instruments
3. Verify no Task accumulation
4. Verify proper cleanup

#### Step 4.2: Integration Testing
1. End-to-end audio conversation test
2. End-to-end text conversation test
3. Tool execution test (automatic)
4. Tool execution test (custom handler)
5. Mode switching test

#### Step 4.3: Documentation
1. Update README
2. Update inline documentation
3. Create migration guide (see Section 7)

---

## 6. Test Strategy

### 6.1 Tests to Remove

| Test File | Tests to Remove | Reason |
|-----------|-----------------|--------|
| `EventEmitterTests.swift` | Handler registration tests | Feature removed |
| `EventEmitterTests.swift` | Handler execution tests | Feature removed |
| `EventEmitterTests.swift` | Handler removal tests | Feature removed |
| `EchoTests.swift` | `when()` method tests | Feature removed |

### 6.2 Tests to Add

#### ToolExecutor Tests
```swift
final class ToolExecutorTests: XCTestCase {
    func testRegisterTool()
    func testExecuteRegisteredTool()
    func testExecuteUnregisteredToolReturnsError()
    func testCustomHandlerOverridesAutomatic()
    func testToolExecutionWithArguments()
}
```

#### Delegate Pattern Tests
```swift
final class RealtimeClientDelegateTests: XCTestCase {
    func testDelegateReceivesToolCall()
    func testDelegateReceivesTranscript()
    func testDelegateReceivesAssistantResponse()
    func testDelegateReceivesSpeechEvents()
}

final class TurnManagerDelegateTests: XCTestCase {
    func testDelegateReceivesInterruptionRequest()
    func testInterruptionTriggersOnUserSpeechDuringAssistant()
}
```

#### Resource Cleanup Tests
```swift
final class ResourceCleanupTests: XCTestCase {
    func testNoOrphanedTasksAfterDisconnect()
    func testRepeatedConnectDisconnectNoMemoryGrowth()
    func testEventEmitterContinuationFinishedOnDeinit()
    func testMessageQueueContinuationsFinishedOnDeinit()
    func testNotificationObserverRemovedOnCleanup()
}
```

#### Callback Pattern Tests
```swift
final class AudioCaptureCallbackTests: XCTestCase {
    func testAudioLevelCallbackFires()
    func testAudioChunkCallbackFires()
    func testCallbacksStopAfterStop()
}

final class WebSocketCallbackTests: XCTestCase {
    func testOnMessageCallbackFires()
    func testOnDisconnectCallbackFires()
    func testCallbacksStopAfterDisconnect()
}
```

### 6.3 Tests to Modify

| Test File | Modification |
|-----------|--------------|
| `ConversationTests.swift` | Remove event listener setup expectations |
| `RealtimeClientTests.swift` | Add delegate mock, verify delegate calls |
| `TurnManagerTests.swift` | Add delegate mock, verify delegate calls |
| `EchoTests.swift` | Change from `when()` to `events` stream |

### 6.4 Integration Test Updates

```swift
final class IntegrationTests: XCTestCase {
    func testFullAudioConversationFlow() async throws {
        let echo = Echo(key: testKey)
        let conversation = try await echo.startConversation(mode: .audio)

        // Collect events via stream (new pattern)
        var receivedEvents: [EchoEvent] = []
        let eventTask = Task {
            for await event in echo.events {
                receivedEvents.append(event)
                if case .assistantStoppedSpeaking = event { break }
            }
        }

        // Trigger conversation
        try await conversation.send("Hello")

        // Wait for completion
        await eventTask.value

        // Verify events received
        XCTAssertTrue(receivedEvents.contains { if case .audioStarted = $0 { return true }; return false })
        XCTAssertTrue(receivedEvents.contains { if case .userStartedSpeaking = $0 { return true }; return false })

        // Cleanup
        await conversation.disconnect()
    }

    func testCustomToolHandler() async throws {
        let echo = Echo(key: testKey)

        // Set custom handler (new pattern)
        echo.toolHandler = { toolCall in
            return "{\"result\": \"custom handled\"}"
        }

        let conversation = try await echo.startConversation(mode: .audio)

        // ... test that custom handler is invoked
    }
}
```

---

## 7. Migration Guide

### 7.1 Overview

This release introduces a simplified event system. Events are now observation-only—you watch what the system does but don't register handlers that participate in the control flow.

**Breaking Changes:**
1. `echo.when()` methods removed
2. `eventEmitter.when()` methods removed
3. Tool handling API changed

### 7.2 Event Observation

#### Before (v1.x)
```swift
let echo = Echo(key: apiKey)

// Register handlers for specific events
echo.when(.audioStarted) { event in
    print("Audio started!")
}

echo.when(.userStartedSpeaking, .userStoppedSpeaking) { event in
    switch event {
    case .userStartedSpeaking:
        print("User speaking")
    case .userStoppedSpeaking:
        print("User stopped")
    default:
        break
    }
}

// Async handlers
echo.when(.error) { event async in
    await logError(event)
}
```

#### After (v2.0)
```swift
let echo = Echo(key: apiKey)

// Single event stream - observe all events
Task {
    for await event in echo.events {
        switch event {
        case .audioStarted:
            print("Audio started!")

        case .userStartedSpeaking:
            print("User speaking")

        case .userStoppedSpeaking:
            print("User stopped")

        case .error(let error):
            await logError(error)

        default:
            break
        }
    }
}
```

#### Migration Steps

1. Remove all `echo.when()` calls
2. Create a single Task that iterates `echo.events`
3. Use `switch` to handle events you care about
4. Use `default` to ignore events you don't need

### 7.3 Tool Handling

#### Before (v1.x) - Automatic
```swift
let echo = Echo(key: apiKey, automaticToolExecution: true)

// Register tool
echo.registerTool(Tool(
    name: "get_weather",
    description: "Gets weather",
    parameters: weatherParams,
    handler: { args in
        return await fetchWeather(args)
    }
))

// Tools execute automatically, results sent automatically
```

#### After (v2.0) - Automatic (Default)
```swift
let echo = Echo(key: apiKey)

// Register tool - same as before
echo.registerTool(Tool(
    name: "get_weather",
    description: "Gets weather",
    parameters: weatherParams,
    handler: { args in
        return await fetchWeather(args)
    }
))

// Tools still execute automatically - no change needed!
```

**No migration required for automatic tool execution.**

#### Before (v1.x) - Custom Handling
```swift
let echo = Echo(key: apiKey, automaticToolExecution: false)

echo.registerTool(weatherTool)

// Custom handler via event
echo.when(call: { toolCall in
    // Custom logic before execution
    if await userApproves(toolCall) {
        return await executeTool(toolCall)
    } else {
        throw ToolError.userDenied
    }
})
```

#### After (v2.0) - Custom Handling
```swift
let echo = Echo(key: apiKey)

echo.registerTool(weatherTool)

// Custom handler via property
echo.toolHandler = { toolCall in
    // Custom logic before execution
    if await userApproves(toolCall) {
        return await executeTool(toolCall)
    } else {
        throw ToolError.userDenied
    }
}
```

#### Migration Steps

1. Replace `automaticToolExecution: false` parameter (removed)
2. Replace `echo.when(call:)` with `echo.toolHandler = { ... }`
3. Handler signature is the same: `(ToolCall) async throws -> String`

### 7.4 EventEmitter Direct Access

#### Before (v1.x)
```swift
// If accessing EventEmitter directly
let emitter = EventEmitter()

emitter.when(.someEvent) { event in
    // handle
}

let handlerId = emitter.when(.otherEvent) { event in
    // handle
}

emitter.removeHandler(handlerId)
emitter.removeAllHandlers()
```

#### After (v2.0)
```swift
// EventEmitter is now emit-only
let emitter = EventEmitter()

// Observe via stream
Task {
    for await event in emitter.events {
        // handle all events
    }
}

// No handler registration
// No handler removal
// Just observe the stream
```

### 7.5 Filtering Events

#### Before (v1.x)
```swift
// Register only for events you want
echo.when(.audioStarted, .audioStopped) { event in
    updateAudioUI(event)
}
```

#### After (v2.0)
```swift
// Filter in your switch statement
Task {
    for await event in echo.events {
        switch event {
        case .audioStarted, .audioStopped:
            updateAudioUI(event)
        default:
            break  // Ignore other events
        }
    }
}

// Or use AsyncSequence methods
Task {
    for await event in echo.events where event.isAudioEvent {
        updateAudioUI(event)
    }
}
```

### 7.6 Multiple Observers

#### Before (v1.x)
```swift
// Multiple handlers for same event
echo.when(.messageFinalized) { event in
    updateChatUI(event)
}

echo.when(.messageFinalized) { event in
    saveToDatabase(event)
}
```

#### After (v2.0)
```swift
// Multiple Tasks observing same stream
Task {
    for await event in echo.events {
        if case .messageFinalized(let message) = event {
            updateChatUI(message)
        }
    }
}

Task {
    for await event in echo.events {
        if case .messageFinalized(let message) = event {
            await saveToDatabase(message)
        }
    }
}
```

### 7.7 Handler Lifecycle

#### Before (v1.x)
```swift
// Handler lived until explicitly removed or Echo deallocated
let id = echo.when(.someEvent) { _ in }
// ... later
// Handlers auto-cleaned on Echo deinit
```

#### After (v2.0)
```swift
// You control the Task lifecycle
let observerTask = Task {
    for await event in echo.events {
        // handle
    }
}

// Cancel when done
observerTask.cancel()

// Or break from the loop
Task {
    for await event in echo.events {
        handleEvent(event)
        if shouldStopObserving {
            break
        }
    }
}
```

### 7.8 Quick Reference

| v1.x Pattern | v2.0 Pattern |
|--------------|--------------|
| `echo.when(.event) { }` | `for await event in echo.events { switch... }` |
| `echo.when(.e1, .e2) { }` | `switch event { case .e1, .e2: ... }` |
| `echo.when(call:) { }` | `echo.toolHandler = { }` |
| `automaticToolExecution: false` | Set `echo.toolHandler` to non-nil |
| `eventEmitter.when() { }` | `for await event in emitter.events { }` |
| `emitter.removeHandler(id)` | `task.cancel()` or `break` from loop |
| Multiple handlers | Multiple Tasks |

### 7.9 Common Migration Patterns

#### Pattern: UI Updates
```swift
// BEFORE
echo.when(.audioStatusChanged) { event in
    DispatchQueue.main.async {
        self.updateAudioIndicator(event)
    }
}

// AFTER
Task { @MainActor in
    for await event in echo.events {
        if case .audioStatusChanged(let status) = event {
            updateAudioIndicator(status)
        }
    }
}
```

#### Pattern: Logging
```swift
// BEFORE
echo.when(handler: { event in
    Logger.log(event)
})

// AFTER
Task.detached(priority: .utility) {
    for await event in echo.events {
        Logger.log(event)
    }
}
```

#### Pattern: Conditional Observation
```swift
// BEFORE
if settings.enableAnalytics {
    echo.when(.toolCallRequested) { event in
        Analytics.track(event)
    }
}

// AFTER
if settings.enableAnalytics {
    Task {
        for await event in echo.events {
            if case .toolCallRequested(let call) = event {
                Analytics.track(call)
            }
        }
    }
}
```

---

## 8. Risk Assessment

### 8.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Delegate retain cycles | Medium | High | Use `weak` references, document ownership |
| Missing event emissions | Low | Medium | Audit all emit() calls, integration tests |
| Callback threading issues | Medium | Medium | Document Sendable requirements, test on various queues |
| Breaking existing apps | High | High | Comprehensive migration guide, clear versioning |

### 8.2 Behavioral Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Users expect `when()` to intercept | Medium | Medium | Documentation, clear naming ("observe" vs "handle") |
| Multiple event stream consumers confusing | Low | Low | Documentation with examples |
| Tool handler timing differences | Low | Medium | Ensure tool execution timing matches v1.x |

### 8.3 Rollback Plan

If critical issues discovered post-release:

1. Patch release with both patterns available (deprecated `when()` restored)
2. Flag for "legacy event mode"
3. Extended deprecation period before removal

---

## Appendix A: File Change Summary

```
Sources/Echo/
├── Echo.swift                           [MAJOR CHANGE]
├── Audio/
│   ├── AudioCapture.swift              [MINOR CHANGE]
│   ├── AudioPlayback.swift             [NO CHANGE]
│   └── AudioProcessor.swift            [NO CHANGE]
├── Core/
│   ├── Conversation.swift              [MAJOR CHANGE]
│   ├── MessageQueue.swift              [MINOR CHANGE]
│   └── TurnManager.swift               [MODERATE CHANGE]
├── Events/
│   ├── EventEmitter.swift              [MAJOR CHANGE]
│   ├── EventHandler.swift              [DELETE]
│   ├── EventType.swift                 [NO CHANGE]
│   └── EchoEvent.swift                 [NO CHANGE]
├── Network/
│   ├── HTTPClient.swift                [NO CHANGE]
│   └── WebSocketManager.swift          [MODERATE CHANGE]
├── Protocols/
│   └── InternalDelegates.swift         [NEW FILE]
├── Realtime/
│   └── RealtimeClient.swift            [MAJOR CHANGE]
├── Responses/
│   └── ResponsesClient.swift           [MINOR CHANGE]
└── Tools/
    ├── Tool.swift                      [NO CHANGE]
    └── ToolExecutor.swift              [NEW FILE]
```

---

## Appendix B: Estimated Effort

| Phase | Estimated Time | Dependencies |
|-------|----------------|--------------|
| Phase 1: Foundation | 2-3 days | None |
| Phase 2: Internal Rewiring | 4-5 days | Phase 1 |
| Phase 3: API Changes | 2-3 days | Phase 2 |
| Phase 4: Validation | 2-3 days | Phase 3 |
| **Total** | **10-14 days** | |

---

## Appendix C: Version Strategy

- **Current:** v1.2.2
- **This Release:** v2.0.0 (major version bump for breaking changes)
- **Deprecation:** No deprecation period (clean break)
