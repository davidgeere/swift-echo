// EventEmitter.swift
// Echo - Event Infrastructure
// Central event dispatch actor for thread-safe event handling

import Foundation

/// Central event dispatcher that manages event handlers and emissions in a thread-safe manner.
/// All event registration and emission goes through this actor to ensure proper concurrency control.
public actor EventEmitter {
    /// Storage for event handlers, organized by event type
    /// Each event type can have multiple handlers
    private var handlers: [EventType: [EventHandler]] = [:]

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

    // MARK: - Handler Registration

    /// Registers a synchronous event handler for a specific event type
    /// - Parameters:
    ///   - eventType: The type of event to listen for
    ///   - handler: The synchronous handler closure to execute when the event is emitted
    /// - Returns: A unique handler ID that can be used to remove the handler later
    @discardableResult
    public func when(
        _ eventType: EventType,
        handler: @escaping EventHandlerClosure
    ) -> UUID {
        let eventHandler = EventHandler(eventType: eventType, handler: handler)
        let handlerId = eventHandler.id

        // Add handler to the list for this event type
        if handlers[eventType] == nil {
            handlers[eventType] = []
        }
        handlers[eventType]?.append(eventHandler)

        if enableLogging {
            log("Registered sync handler for \(eventType.rawValue)")
        }

        return handlerId
    }

    /// Registers an asynchronous event handler for a specific event type
    /// - Parameters:
    ///   - eventType: The type of event to listen for
    ///   - handler: The asynchronous handler closure to execute when the event is emitted
    /// - Returns: A unique handler ID that can be used to remove the handler later
    @discardableResult
    public func when(
        _ eventType: EventType,
        asyncHandler: @escaping AsyncEventHandlerClosure
    ) -> UUID {
        let eventHandler = EventHandler(eventType: eventType, asyncHandler: asyncHandler)
        let handlerId = eventHandler.id

        // Add handler to the list for this event type
        if handlers[eventType] == nil {
            handlers[eventType] = []
        }
        handlers[eventType]?.append(eventHandler)

        if enableLogging {
            log("Registered async handler for \(eventType.rawValue)")
        }

        return handlerId
    }

    /// Registers a synchronous event handler for multiple event types
    /// - Parameters:
    ///   - eventTypes: Array of event types to listen for
    ///   - handler: The synchronous handler closure to execute when any of the events are emitted
    /// - Returns: Array of unique handler IDs (one per event type) that can be used to remove handlers later
    @discardableResult
    public func when(
        _ eventTypes: [EventType],
        handler: @escaping EventHandlerClosure
    ) -> [UUID] {
        return eventTypes.map { eventType in
            when(eventType, handler: handler)
        }
    }

    /// Registers an asynchronous event handler for multiple event types
    /// - Parameters:
    ///   - eventTypes: Array of event types to listen for
    ///   - asyncHandler: The asynchronous handler closure to execute when any of the events are emitted
    /// - Returns: Array of unique handler IDs (one per event type) that can be used to remove handlers later
    @discardableResult
    public func when(
        _ eventTypes: [EventType],
        asyncHandler: @escaping AsyncEventHandlerClosure
    ) -> [UUID] {
        return eventTypes.map { eventType in
            when(eventType, asyncHandler: asyncHandler)
        }
    }

    /// Registers a synchronous event handler for multiple event types (variadic)
    /// - Parameters:
    ///   - eventTypes: Variadic list of event types to listen for
    ///   - handler: The synchronous handler closure to execute when any of the events are emitted
    /// - Returns: Array of unique handler IDs (one per event type) that can be used to remove handlers later
    @discardableResult
    public func when(
        _ eventTypes: EventType...,
        handler: @escaping EventHandlerClosure
    ) -> [UUID] {
        return when(eventTypes, handler: handler)
    }

    /// Registers an asynchronous event handler for multiple event types (variadic)
    /// - Parameters:
    ///   - eventTypes: Variadic list of event types to listen for
    ///   - asyncHandler: The asynchronous handler closure to execute when any of the events are emitted
    /// - Returns: Array of unique handler IDs (one per event type) that can be used to remove handlers later
    @discardableResult
    public func when(
        _ eventTypes: EventType...,
        asyncHandler: @escaping AsyncEventHandlerClosure
    ) -> [UUID] {
        return when(eventTypes, asyncHandler: asyncHandler)
    }

    // MARK: - Handler Removal

    /// Removes a specific event handler by its ID
    /// - Parameter handlerId: The UUID returned when the handler was registered
    /// - Returns: True if the handler was found and removed, false otherwise
    @discardableResult
    public func removeHandler(_ handlerId: UUID) -> Bool {
        for (eventType, eventHandlers) in handlers {
            if let index = eventHandlers.firstIndex(where: { $0.id == handlerId }) {
                handlers[eventType]?.remove(at: index)

                if enableLogging {
                    log("Removed handler \(handlerId) for \(eventType.rawValue)")
                }

                return true
            }
        }
        return false
    }

    /// Removes all handlers for a specific event type
    /// - Parameter eventType: The event type to clear handlers for
    /// - Returns: The number of handlers removed
    @discardableResult
    public func removeAllHandlers(for eventType: EventType) -> Int {
        let count = handlers[eventType]?.count ?? 0
        handlers[eventType] = nil

        if enableLogging && count > 0 {
            log("Removed \(count) handler(s) for \(eventType.rawValue)")
        }

        return count
    }

    /// Removes all handlers for all event types
    /// - Returns: The total number of handlers removed
    @discardableResult
    public func removeAllHandlers() -> Int {
        let total = handlers.values.reduce(0) { $0 + $1.count }
        handlers.removeAll()

        if enableLogging && total > 0 {
            log("Removed all \(total) handler(s)")
        }

        return total
    }

    // MARK: - Event Emission

    /// Emits an event to all registered handlers for that event type
    /// Handlers are executed asynchronously in the order they were registered
    /// - Parameter event: The event to emit
    public func emit(_ event: EchoEvent) async {
        let eventType = event.type
        let eventHandlers = handlers[eventType] ?? []

        if enableLogging {
            log("Emitting event: \(eventType.rawValue) to \(eventHandlers.count) handler(s)")
        }

        // Yield event to stream subscribers
        eventContinuation?.yield(event)

        // Execute all handlers for this event type
        for handler in eventHandlers {
            await handler.execute(event: event)
        }
    }

    /// Emits an event to all registered handlers, but doesn't wait for completion
    /// Use this for fire-and-forget scenarios
    /// - Parameter event: The event to emit
    public nonisolated func emitAsync(_ event: EchoEvent) {
        Task {
            await self.emit(event)
        }
    }

    // MARK: - Diagnostics

    /// Returns the number of handlers registered for a specific event type
    /// - Parameter eventType: The event type to query
    /// - Returns: The number of registered handlers
    public func handlerCount(for eventType: EventType) -> Int {
        return handlers[eventType]?.count ?? 0
    }

    /// Returns the total number of handlers registered across all event types
    /// - Returns: The total number of registered handlers
    public func totalHandlerCount() -> Int {
        return handlers.values.reduce(0) { $0 + $1.count }
    }

    /// Returns all event types that have at least one handler registered
    /// - Returns: Array of event types with registered handlers
    public func registeredEventTypes() -> [EventType] {
        return handlers.keys.filter { (handlers[$0]?.count ?? 0) > 0 }
    }

    // MARK: - Private Helpers

    private func log(_ message: String) {
        print("[EventEmitter] \(message)")
    }
}
