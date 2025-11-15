// EventHandler.swift
// Echo - Event Infrastructure
// Handler closure types and wrapper for event callbacks

import Foundation

// MARK: - Handler Type Aliases

/// Synchronous event handler closure type
/// - Parameter event: The event that was emitted
public typealias EventHandlerClosure = @Sendable (EchoEvent) -> Void

/// Asynchronous event handler closure type
/// - Parameter event: The event that was emitted
public typealias AsyncEventHandlerClosure = @Sendable (EchoEvent) async -> Void

// MARK: - Event Handler Wrapper

/// Wraps both synchronous and asynchronous event handlers in a unified type
/// This allows the EventEmitter to store and execute both handler types uniformly
actor EventHandler {
    /// Unique identifier for this handler (used for removal)
    let id: UUID

    /// The type of event this handler is registered for
    let eventType: EventType

    /// The actual handler implementation
    private let handler: HandlerType

    /// Discriminated union for sync vs async handlers
    private enum HandlerType {
        case sync(EventHandlerClosure)
        case async(AsyncEventHandlerClosure)
    }

    // MARK: - Initialization

    /// Creates a synchronous event handler
    /// - Parameters:
    ///   - eventType: The type of event to handle
    ///   - handler: The synchronous handler closure
    init(eventType: EventType, handler: @escaping EventHandlerClosure) {
        self.id = UUID()
        self.eventType = eventType
        self.handler = .sync(handler)
    }

    /// Creates an asynchronous event handler
    /// - Parameters:
    ///   - eventType: The type of event to handle
    ///   - handler: The asynchronous handler closure
    init(eventType: EventType, asyncHandler: @escaping AsyncEventHandlerClosure) {
        self.id = UUID()
        self.eventType = eventType
        self.handler = .async(asyncHandler)
    }

    // MARK: - Handler Execution

    /// Executes the handler with the given event
    /// - Parameter event: The event to pass to the handler
    func execute(event: EchoEvent) async {
        switch handler {
        case .sync(let syncHandler):
            // Execute synchronous handler
            syncHandler(event)

        case .async(let asyncHandler):
            // Execute asynchronous handler
            await asyncHandler(event)
        }
    }
}
