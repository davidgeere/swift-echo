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

    /// Event emitter for publishing turn changes
    private let eventEmitter: EventEmitter

    /// Timer task for manual mode timeouts
    private var turnTimer: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new turn manager
    /// - Parameters:
    ///   - mode: The turn management mode
    ///   - eventEmitter: Event emitter for publishing events
    public init(mode: TurnMode, eventEmitter: EventEmitter) {
        self.mode = mode
        self.eventEmitter = eventEmitter
    }

    // MARK: - Turn Management

    /// Called when user starts speaking
    public func handleUserStartedSpeaking() async {
        guard currentSpeaker != .user else { return }

        // Check if we should interrupt assistant BEFORE changing currentSpeaker
        let wasAssistantSpeaking = (currentSpeaker == .assistant)

        currentSpeaker = .user
        turnTimer?.cancel()

        // Emit BOTH events - specific and turn change
        await eventEmitter.emit(.userStartedSpeaking)
        await eventEmitter.emit(.turnChanged(speaker: .user))

        // Interrupt assistant if needed
        if case .automatic = mode {
            if wasAssistantSpeaking {
                await eventEmitter.emit(.assistantInterrupted)
            }
        }
    }

    /// Called when user stops speaking
    public func handleUserStoppedSpeaking() async {
        guard currentSpeaker == .user else { return }

        // Emit event
        await eventEmitter.emit(.userStoppedSpeaking)

        switch mode {
        case .automatic:
            // VAD will automatically trigger response
            // Server will send speech_stopped event
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

        // Emit BOTH events - specific and turn change
        await eventEmitter.emit(.assistantStartedSpeaking)
        await eventEmitter.emit(.turnChanged(speaker: .assistant))
    }

    /// Called when assistant finishes speaking
    public func handleAssistantFinishedSpeaking() async {
        guard currentSpeaker == .assistant else { return }

        currentSpeaker = .none

        await eventEmitter.emit(.assistantStoppedSpeaking)
        await eventEmitter.emit(.turnChanged(speaker: .none))
    }

    /// Manually ends the user's turn (for manual mode)
    public func endUserTurn() async {
        guard currentSpeaker == .user else { return }

        currentSpeaker = .none
        turnTimer?.cancel()

        // Signal that user turn is complete
        await eventEmitter.emit(.turnEnded)
    }

    /// Manually interrupts the assistant (for interruption support)
    public func interruptAssistant() async {
        guard currentSpeaker == .assistant else { return }

        currentSpeaker = .none
        turnTimer?.cancel()

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
