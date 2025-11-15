// MessageQueue.swift
// Echo
//
// Central message queue ensuring proper message sequencing.
// CRITICAL: Handles out-of-order arrival (assistant response before user transcript)
//

import Foundation

/// Actor-based message queue for thread-safe message sequencing.
///
/// This is the most critical component of Echo, ensuring proper message ordering
/// especially in audio mode where transcription may complete after assistant response begins.
public actor MessageQueue {
    // MARK: - Private Properties

    private var pendingMessages: [PendingMessage] = []
    private var completedMessages: [Message] = []
    private var sequenceNumber: Int = 0
    private let eventEmitter: EventEmitter
    private var continuations: [UUID: AsyncStream<Message>.Continuation] = [:]

    // MARK: - Initialization

    public init(eventEmitter: EventEmitter) {
        self.eventEmitter = eventEmitter
    }

    // MARK: - Nested Types

    /// A message waiting for data to arrive before finalization
    struct PendingMessage {
        let id: String
        let role: MessageRole
        var text: String?
        var audioData: Data?
        var transcriptStatus: TranscriptStatus
        let timestamp: Date
        let sequenceNumber: Int
    }

    /// Status of transcript processing for a message
    public enum TranscriptStatus: Sendable {
        /// Transcript processing has not yet started
        case notStarted

        /// Transcript is currently being processed
        case inProgress

        /// Transcript processing is complete
        case completed

        /// Transcript is not applicable (text-only message)
        case notApplicable
    }

    // MARK: - Public Methods

    /// Enqueues a new message to the queue
    ///
    /// - Parameters:
    ///   - id: Optional custom ID (e.g., from Realtime API), defaults to UUID
    ///   - role: The role of the message sender
    ///   - text: Optional text content
    ///   - audioData: Optional audio data
    ///   - transcriptStatus: Status of transcript processing (default: .notApplicable)
    /// - Returns: The unique identifier for the enqueued message
    @discardableResult
    public func enqueue(
        id: String? = nil,
        role: MessageRole,
        text: String? = nil,
        audioData: Data? = nil,
        transcriptStatus: TranscriptStatus = .notApplicable
    ) -> String {
        let messageId = id ?? UUID().uuidString
        let pending = PendingMessage(
            id: messageId,
            role: role,
            text: text,
            audioData: audioData,
            transcriptStatus: transcriptStatus,
            timestamp: Date(),
            sequenceNumber: sequenceNumber
        )
        sequenceNumber += 1
        pendingMessages.append(pending)

        // Try to finalize messages after adding
        tryFinalizePendingMessages()

        return messageId
    }

    /// Updates the transcript for a pending message
    ///
    /// - Parameters:
    ///   - id: The identifier of the message to update
    ///   - transcript: The completed transcript text
    public func updateTranscript(id: String, transcript: String) {
        guard let index = pendingMessages.firstIndex(where: { $0.id == id }) else {
            return
        }

        pendingMessages[index].text = transcript
        pendingMessages[index].transcriptStatus = .completed

        // Try to finalize messages after update
        tryFinalizePendingMessages()
    }

    /// Returns all completed messages ordered by sequence number
    ///
    /// - Returns: Array of messages sorted by sequence number
    public func getOrderedMessages() -> [Message] {
        return completedMessages.sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    /// Returns a specific message by ID
    /// - Parameter id: The message ID to retrieve
    /// - Returns: The message if found, nil otherwise
    public func getMessage(byId id: String) -> Message? {
        return completedMessages.first { $0.id == id }
    }
    
    /// Returns the count of pending messages
    ///
    /// - Returns: Number of messages waiting to be finalized
    public func pendingCount() -> Int {
        return pendingMessages.count
    }

    /// Returns the count of completed messages
    ///
    /// - Returns: Number of finalized messages
    public func completedCount() -> Int {
        return completedMessages.count
    }

    /// Clears all messages from the queue
    public func clear() {
        pendingMessages.removeAll()
        completedMessages.removeAll()
        sequenceNumber = 0
    }

    // MARK: - Private Methods

    /// Attempts to finalize pending messages in sequence order
    ///
    /// Messages are only finalized when:
    /// - Their transcript is completed, OR
    /// - Transcript is not applicable (text-only message)
    ///
    /// This ensures messages are emitted in the correct order regardless of
    /// when transcripts complete (critical for audio mode).
    private func tryFinalizePendingMessages() {
        while let first = pendingMessages.first {
            // Can only finalize if transcript is complete or not needed
            guard first.transcriptStatus == .completed ||
                  first.transcriptStatus == .notApplicable else {
                // Cannot finalize - must wait for transcript
                break
            }

            // Move to completed
            let message = Message(
                id: first.id,
                role: first.role,
                text: first.text ?? "",
                audioData: first.audioData,
                timestamp: first.timestamp,
                sequenceNumber: first.sequenceNumber
            )
            completedMessages.append(message)
            pendingMessages.removeFirst()

            // Emit message finalized event
            Task {
                await eventEmitter.emit(.messageFinalized(message: message))
            }

            // Yield to all active continuations
            for (_, continuation) in continuations {
                continuation.yield(message)
            }
        }
    }

    /// Subscribe to new messages as they are finalized
    /// - Parameter continuation: The continuation to yield messages to
    public func subscribe(continuation: AsyncStream<Message>.Continuation) {
        let id = UUID()
        continuations[id] = continuation

        // Set up termination handler to remove continuation when stream is cancelled
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeContinuation(id)
            }
        }

        // Yield all existing completed messages to new subscribers
        for message in completedMessages {
            continuation.yield(message)
        }
    }

    /// Remove a continuation from the dictionary
    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
