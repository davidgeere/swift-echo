// EventEmitter.swift
// Echo - Event Infrastructure
// Pure sink event emitter - emit only, no internal handlers (v2.0 Architecture)

import Foundation

/// Pure sink event emitter for external observation.
/// Events are fire-and-forget - no internal handlers, no spawned Tasks.
/// SDK users observe events via the `events` AsyncStream.
public actor EventEmitter {
    /// Logger for debugging event emissions (optional)
    private let enableLogging: Bool

    /// Continuation for the events stream
    private var eventContinuation: AsyncStream<EchoEvent>.Continuation?

    /// Stream of all emitted events.
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

    /// Emits an event to the stream for external observers.
    /// This is fire-and-forget - no handlers are executed internally.
    /// - Parameter event: The event to emit
    public func emit(_ event: EchoEvent) async {
        if enableLogging {
            log("Emitting event: \(event.type.rawValue)")
        }

        // Yield event to stream subscribers only
        eventContinuation?.yield(event)
    }

    /// Emits an event to the stream without waiting (nonisolated convenience).
    /// Use this for fire-and-forget scenarios where you don't need to wait.
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
