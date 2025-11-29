// EventEmitter.swift
// Echo - Event Infrastructure
// Pure sink event emitter - events are observations, not commands

import Foundation

/// Central event emitter that acts as a pure sink for event notifications.
/// 
/// Events are for observation only - SDK users watch what the system does
/// but don't participate in control flow. Internal coordination uses
/// direct method calls via delegates instead.
///
/// ## Usage
/// ```swift
/// // Observe events via the async stream
/// Task {
///     for await event in echo.events {
///         switch event {
///         case .userStartedSpeaking:
///             updateUI()
///         case .error(let error):
///             handleError(error)
///         default:
///             break
///         }
///     }
/// }
/// ```
public actor EventEmitter {
    // MARK: - Properties
    
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
    /// This is a fire-and-forget operation - the event is yielded to the stream
    /// and the method returns immediately.
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
