// TurnManager.swift
// Echo - Core
// Manages speaking turns in conversations with VAD support

import Foundation

/// Manages speaking turns in audio conversations
public actor TurnManager {
    // MARK: - Types

    /// Represents who is currently speaking
    public enum Speaker: String, Sendable {
        /// User is speaking
        case user

        /// Assistant is speaking
        case assistant

        /// No one is speaking
        case none
    }

    /// Turn management mode
    public enum TurnMode: Sendable {
        /// Automatic turn detection using VAD
        case automatic(VADConfiguration)

        /// Manual turn control with optional timeout
        case manual(timeout: Duration?)

        /// Turn detection disabled
        case disabled
    }

    // MARK: - Properties

    /// Current speaker
    private(set) var currentSpeaker: Speaker = .none

    /// Turn management mode
    private(set) var mode: TurnMode

    /// Event emitter for publishing turn changes (notifications only)
    private let eventEmitter: EventEmitter

    /// Delegate for requesting actions (direct calls, not events)
    private weak var delegate: (any TurnManagerDelegate)?

    /// Timer task for manual mode timeouts
    private var turnTimer: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new turn manager
    /// - Parameters:
    ///   - mode: The turn management mode
    ///   - eventEmitter: Event emitter for publishing events
    ///   - delegate: Optional delegate for action requests
    public init(
        mode: TurnMode,
        eventEmitter: EventEmitter,
        delegate: (any TurnManagerDelegate)? = nil
    ) {
        self.mode = mode
        self.eventEmitter = eventEmitter
        self.delegate = delegate
    }
    
    deinit {
        // Cancel any pending timer task
        turnTimer?.cancel()
    }

    /// Sets the delegate for action requests
    /// - Parameter delegate: The delegate to set
    public func setDelegate(_ delegate: any TurnManagerDelegate) {
        self.delegate = delegate
    }

    // MARK: - Turn Management

    /// Called when user starts speaking
    public func handleUserStartedSpeaking() async {
        guard currentSpeaker != .user else { return }

        // Check if we should interrupt assistant BEFORE changing currentSpeaker
        let wasAssistantSpeaking = (currentSpeaker == .assistant)

        currentSpeaker = .user
        turnTimer?.cancel()

        // Emit notification events (for SDK users)
        await eventEmitter.emit(.userStartedSpeaking)
        await eventEmitter.emit(.turnChanged(speaker: .user))

        // Request interruption via delegate (direct call, not event)
        if case .automatic = mode {
            if wasAssistantSpeaking {
                // Notify delegate directly instead of emitting .assistantInterrupted
                await delegate?.turnManagerDidRequestInterruption(self)
                // Also emit for SDK users who want to observe
                await eventEmitter.emit(.assistantInterrupted)
            }
        }
    }

    /// Called when user stops speaking
    public func handleUserStoppedSpeaking() async {
        guard currentSpeaker == .user else { return }

        // Emit notification event
        await eventEmitter.emit(.userStoppedSpeaking)

        switch mode {
        case .automatic:
            // VAD will automatically trigger response
            break

        case .manual(let timeout):
            // Start optional timeout
            if let timeout = timeout {
                turnTimer = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        await endUserTurn()
                    } catch {
                        // Task was cancelled
                    }
                }
            }

        case .disabled:
            break
        }
    }

    /// Called when assistant starts speaking
    public func handleAssistantStartedSpeaking() async {
        guard currentSpeaker != .assistant else { return }

        currentSpeaker = .assistant
        turnTimer?.cancel()

        // Emit notification events (for SDK users)
        await eventEmitter.emit(.assistantStartedSpeaking)
        await eventEmitter.emit(.turnChanged(speaker: .assistant))
    }

    /// Called when assistant finishes speaking
    public func handleAssistantFinishedSpeaking() async {
        guard currentSpeaker == .assistant else { return }

        currentSpeaker = .none

        // Emit notification events (for SDK users)
        await eventEmitter.emit(.assistantStoppedSpeaking)
        await eventEmitter.emit(.turnChanged(speaker: .none))
    }

    /// Manually ends the user's turn (for manual mode)
    public func endUserTurn() async {
        guard currentSpeaker == .user else { return }

        currentSpeaker = .none
        turnTimer?.cancel()

        // Notify delegate directly
        await delegate?.turnManagerDidEndUserTurn(self)
        
        // Signal that user turn is complete (notification for SDK users)
        await eventEmitter.emit(.turnEnded)
    }

    /// Manually interrupts the assistant (for interruption support)
    public func interruptAssistant() async {
        guard currentSpeaker == .assistant else { return }

        currentSpeaker = .none
        turnTimer?.cancel()

        // Notify delegate directly
        await delegate?.turnManagerDidRequestInterruption(self)
        
        // Emit notification for SDK users
        await eventEmitter.emit(.assistantInterrupted)
    }

    /// Updates the turn mode
    /// - Parameter newMode: The new turn mode
    public func updateMode(_ newMode: TurnMode) {
        mode = newMode
        turnTimer?.cancel()
    }

    /// Gets the current speaker
    /// - Returns: The current speaker
    public func getCurrentSpeaker() -> Speaker {
        return currentSpeaker
    }
}
