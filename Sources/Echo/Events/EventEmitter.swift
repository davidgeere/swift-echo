// EventEmitter.swift
// Echo - Event Infrastructure
// Pure sink event emitter - events are observations, not commands
// Supports multiple subscribers via broadcast pattern

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
///
/// ## Multi-Subscriber Support
/// Each call to `events` creates a NEW AsyncStream that receives ALL events.
/// This allows multiple consumers to subscribe independently without competing
/// for events. Each subscriber receives every event that's emitted after they
/// subscribe.
public actor EventEmitter {
    // MARK: - Properties
    
    /// Logger for debugging event emissions (optional)
    private let enableLogging: Bool

    /// All active subscriber continuations
    /// Each subscriber gets their own continuation so events are broadcast to all
    private var subscribers: [UUID: AsyncStream<EchoEvent>.Continuation] = [:]

    // MARK: - Initialization

    /// Creates a new EventEmitter
    /// - Parameter enableLogging: Whether to log event emissions for debugging
    public init(enableLogging: Bool = false) {
        self.enableLogging = enableLogging
    }

    // MARK: - Subscription

    /// Stream of all emitted events
    /// 
    /// Each call to this property creates a NEW independent stream.
    /// Multiple consumers can subscribe simultaneously - each receives all events.
    /// 
    /// Use this to observe all events: `for await event in emitter.events { ... }`
    public nonisolated var events: AsyncStream<EchoEvent> {
        AsyncStream { continuation in
            let id = UUID()
            
            // Register this continuation
            Task {
                await self.addSubscriber(id: id, continuation: continuation)
            }
            
            // Remove when cancelled or finished
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.removeSubscriber(id: id)
                }
            }
        }
    }

    /// Adds a new subscriber
    private func addSubscriber(id: UUID, continuation: AsyncStream<EchoEvent>.Continuation) {
        subscribers[id] = continuation
        if enableLogging {
            log("Added subscriber \(id), total: \(subscribers.count)")
        }
    }

    /// Removes a subscriber
    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
        if enableLogging {
            log("Removed subscriber \(id), total: \(subscribers.count)")
        }
    }

    // MARK: - Event Emission

    /// Emits an event to all stream subscribers
    /// This is a fire-and-forget operation - the event is yielded to all streams
    /// and the method returns immediately.
    /// - Parameter event: The event to emit
    public func emit(_ event: EchoEvent) async {
        if enableLogging {
            log("Emitting event: \(event.type.rawValue) to \(subscribers.count) subscribers")
        }

        // Yield event to ALL subscribers
        for (_, continuation) in subscribers {
            continuation.yield(event)
        }
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
