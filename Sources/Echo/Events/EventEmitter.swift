// EventEmitter.swift
// Echo - Event Infrastructure
// Central event dispatch actor for thread-safe event emission (pure sink)

import Foundation

/// Central event dispatcher that emits events in a thread-safe manner.
/// 
/// ## Architecture
/// EventEmitter is a **pure sink** - it only receives events via `emit()` and yields them
/// to stream subscribers. It does NOT register handlers or participate in control flow.
/// 
/// ## Usage
/// ```swift
/// // Observe events
/// Task {
///     for await event in echo.events {
///         switch event {
///         case .userStartedSpeaking:
///             updateUI()
///         default:
///             break
///         }
///     }
/// }
/// ```
/// 
/// ## Migration from v1.x
/// - `when()` methods have been removed
/// - Use `events` stream with `for await` instead
/// - See Migration Guide for details
public actor EventEmitter {
    /// Logger for debugging event emissions (optional)
    private let enableLogging: Bool

    /// Continuation for the events stream
    private var eventContinuation: AsyncStream<EchoEvent>.Continuation?

    /// Stream of all emitted events
    /// Use this to observe all events: `for await event in emitter.events { ... }`
    public nonisolated let events: AsyncStream<EchoEvent>

    // MARK: - Initialization

    /// Creates a new EventEmitter
    /// - Parameter enableLogging: Whether to log event emissions for debugging
    public init(enableLogging: Bool = false) {
        self.enableLogging = enableLogging

        // Create the events stream
        var continuation: AsyncStream<EchoEvent>.Continuation?
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation?.finish()
    }

    // MARK: - Event Emission

    /// Emits an event to all stream subscribers
    /// This is a fire-and-forget operation - it yields to the continuation and returns immediately.
    /// - Parameter event: The event to emit
    public func emit(_ event: EchoEvent) async {
        if enableLogging {
            log("Emitting event: \(event.type.rawValue)")
        }

        // Yield event to stream subscribers
        eventContinuation?.yield(event)
    }

    /// Emits an event to all stream subscribers without waiting
    /// Use this for fire-and-forget scenarios from non-async contexts
    /// - Parameter event: The event to emit
    public nonisolated func emitAsync(_ event: EchoEvent) {
        Task {
            await self.emit(event)
        }
    }

    // MARK: - Private Helpers

    private func log(_ message: String) {
        print("[EventEmitter] \(message)")
    }
}
