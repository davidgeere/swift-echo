// EventEmitter.swift
// Echo - Event Infrastructure
// Pure sink event emitter for external notifications (fire-and-forget)

import Foundation

/// Central event dispatcher that emits events to external observers.
/// 
/// This is a **pure sink** - it only emits events, it does not handle them internally.
/// SDK users observe events via the `events` stream; internal coordination uses
/// direct method calls and delegates, not event handlers.
///
/// ## Usage
/// ```swift
/// // External observation (SDK users)
/// Task {
///     for await event in emitter.events {
///         switch event {
///         case .userStartedSpeaking:
///             updateUI()
///         default:
///             break
///         }
///     }
/// }
///
/// // Internal emission (library components)
/// await emitter.emit(.userStartedSpeaking)
/// ```
public actor EventEmitter {
    // MARK: - Properties
    
    /// Continuation for the events stream
    private var eventContinuation: AsyncStream<EchoEvent>.Continuation?
    
    /// Stream of all emitted events
    /// Use this to observe all events: `for await event in emitter.events { ... }`
    public nonisolated let events: AsyncStream<EchoEvent>
    
    /// Logger for debugging event emissions (optional)
    private let enableLogging: Bool
    
    // MARK: - Initialization
    
    /// Creates a new EventEmitter
    /// - Parameter enableLogging: Whether to log event emissions for debugging
    public init(enableLogging: Bool = false) {
        self.enableLogging = enableLogging
        
        // Create the events stream with buffering
        var continuation: AsyncStream<EchoEvent>.Continuation?
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(100)) { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }
    
    deinit {
        // Finish the continuation to signal stream completion
        eventContinuation?.finish()
    }
    
    // MARK: - Event Emission
    
    /// Emits an event to all stream subscribers
    /// This is fire-and-forget - the event is yielded to the stream and returns immediately.
    /// - Parameter event: The event to emit
    public func emit(_ event: EchoEvent) async {
        if enableLogging {
            log("Emitting event: \(event.type.rawValue)")
        }
        
        // Yield event to stream subscribers
        eventContinuation?.yield(event)
    }
    
    /// Emits an event without waiting (nonisolated convenience)
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

// MARK: - Legacy Handler Types (Deprecated)

/// Synchronous event handler closure type
/// - Parameter event: The event that was emitted
/// - Note: Deprecated in v2.0. Use `for await event in emitter.events` instead.
@available(*, deprecated, message: "Use events stream instead: for await event in emitter.events { ... }")
public typealias EventHandlerClosure = @Sendable (EchoEvent) -> Void

/// Asynchronous event handler closure type
/// - Parameter event: The event that was emitted
/// - Note: Deprecated in v2.0. Use `for await event in emitter.events` instead.
@available(*, deprecated, message: "Use events stream instead: for await event in emitter.events { ... }")
public typealias AsyncEventHandlerClosure = @Sendable (EchoEvent) async -> Void
