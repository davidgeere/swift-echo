// MessageQueueTests.swift
// EchoTests
//
// Comprehensive tests for MessageQueue component
//

import Testing
import Foundation
@testable import Echo

@Suite("Message Queue")
struct MessageQueueTests {

    // MARK: - Basic Functionality Tests

    @Test("Messages are enqueued with unique IDs")
    func testEnqueueGeneratesUniqueIDs() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        let id1 = await queue.enqueue(role: .user, text: "First message")
        let id2 = await queue.enqueue(role: .assistant, text: "Second message")
        let id3 = await queue.enqueue(role: .user, text: "Third message")

        #expect(id1 != id2)
        #expect(id2 != id3)
        #expect(id1 != id3)
    }

    @Test("Messages are ordered correctly by sequence number")
    func testMessageOrdering() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(role: .user, text: "First")
        await queue.enqueue(role: .assistant, text: "Second")
        await queue.enqueue(role: .user, text: "Third")

        let messages = await queue.getOrderedMessages()

        #expect(messages.count == 3)
        #expect(messages[0].text == "First")
        #expect(messages[0].role == .user)
        #expect(messages[0].sequenceNumber == 0)

        #expect(messages[1].text == "Second")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].sequenceNumber == 1)

        #expect(messages[2].text == "Third")
        #expect(messages[2].role == .user)
        #expect(messages[2].sequenceNumber == 2)
    }

    @Test("Text-only messages are finalized immediately")
    func testTextOnlyMessagesFinalized() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(role: .user, text: "Hello")

        let messages = await queue.getOrderedMessages()
        let pending = await queue.pendingCount()

        #expect(messages.count == 1)
        #expect(pending == 0)
        #expect(messages[0].text == "Hello")
    }

    // MARK: - Out-of-Order Transcript Tests (CRITICAL)

    @Test("Assistant response arrives before user transcript completes")
    func testOutOfOrderTranscripts() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        // User message with pending transcript
        let userId = await queue.enqueue(
            role: .user,
            audioData: Data([1, 2, 3, 4]),
            transcriptStatus: .inProgress
        )

        // Assistant starts responding BEFORE transcript completes (real scenario!)
        await queue.enqueue(
            role: .assistant,
            text: "I understand your question."
        )

        // Both messages should be pending (assistant waits for user transcript)
        var messages = await queue.getOrderedMessages()
        var pending = await queue.pendingCount()

        #expect(messages.isEmpty, "No messages should be finalized yet")
        #expect(pending == 2, "Both messages should be pending")

        // Now user transcript completes
        await queue.updateTranscript(id: userId, transcript: "What is the weather?")

        // Both messages should now be finalized in correct order
        messages = await queue.getOrderedMessages()
        pending = await queue.pendingCount()

        #expect(messages.count == 2, "Both messages should now be finalized")
        #expect(pending == 0, "No pending messages remain")
        #expect(messages[0].role == .user, "User message should be first")
        #expect(messages[0].text == "What is the weather?")
        #expect(messages[1].role == .assistant, "Assistant message should be second")
        #expect(messages[1].text == "I understand your question.")
    }

    @Test("Multiple pending messages finalize in correct sequence")
    func testMultiplePendingMessages() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        // Create three messages with pending transcripts
        let user1Id = await queue.enqueue(
            role: .user,
            audioData: Data([1]),
            transcriptStatus: .inProgress
        )

        let assistant1Id = await queue.enqueue(
            role: .assistant,
            text: "Response 1"
        )

        let user2Id = await queue.enqueue(
            role: .user,
            audioData: Data([2]),
            transcriptStatus: .inProgress
        )

        // All should be pending
        var messages = await queue.getOrderedMessages()
        #expect(messages.isEmpty)

        // Complete first user transcript
        await queue.updateTranscript(id: user1Id, transcript: "Question 1")

        // First two messages should finalize
        messages = await queue.getOrderedMessages()
        #expect(messages.count == 2)
        #expect(messages[0].text == "Question 1")
        #expect(messages[1].text == "Response 1")

        // Third message still pending
        var pending = await queue.pendingCount()
        #expect(pending == 1)

        // Complete second user transcript
        await queue.updateTranscript(id: user2Id, transcript: "Question 2")

        // All messages finalized
        messages = await queue.getOrderedMessages()
        pending = await queue.pendingCount()
        #expect(messages.count == 3)
        #expect(pending == 0)
        #expect(messages[2].text == "Question 2")
    }

    @Test("Transcripts can complete in reverse order")
    func testReverseOrderTranscriptCompletion() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        // Two user messages with pending transcripts
        let user1Id = await queue.enqueue(
            role: .user,
            audioData: Data([1]),
            transcriptStatus: .inProgress
        )

        let user2Id = await queue.enqueue(
            role: .user,
            audioData: Data([2]),
            transcriptStatus: .inProgress
        )

        // Complete SECOND transcript first
        await queue.updateTranscript(id: user2Id, transcript: "Second question")

        // First message still blocks everything
        var messages = await queue.getOrderedMessages()
        #expect(messages.isEmpty, "First message blocks finalization")

        // Complete first transcript
        await queue.updateTranscript(id: user1Id, transcript: "First question")

        // Both should finalize in correct order
        messages = await queue.getOrderedMessages()
        #expect(messages.count == 2)
        #expect(messages[0].text == "First question")
        #expect(messages[1].text == "Second question")
    }

    // MARK: - Transcript Status Tests

    @Test("Messages with notApplicable transcript status finalize immediately")
    func testNotApplicableTranscriptStatus() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(
            role: .user,
            text: "Text message",
            transcriptStatus: .notApplicable
        )

        let messages = await queue.getOrderedMessages()
        #expect(messages.count == 1)
    }

    @Test("Messages with notStarted status wait for update")
    func testNotStartedTranscriptStatus() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        let userId = await queue.enqueue(
            role: .user,
            audioData: Data([1, 2, 3]),
            transcriptStatus: .notStarted
        )

        var messages = await queue.getOrderedMessages()
        #expect(messages.isEmpty)

        // Update transcript
        await queue.updateTranscript(id: userId, transcript: "Now complete")

        messages = await queue.getOrderedMessages()
        #expect(messages.count == 1)
        #expect(messages[0].text == "Now complete")
    }

    // MARK: - Concurrent Operations Tests

    @Test("Concurrent enqueue operations maintain sequence")
    func testConcurrentEnqueue() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        // Enqueue multiple messages concurrently
        await withTaskGroup(of: String.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await queue.enqueue(role: .user, text: "Message \(i)")
                }
            }
        }

        let messages = await queue.getOrderedMessages()
        #expect(messages.count == 10)

        // Verify sequence numbers are continuous
        for (index, message) in messages.enumerated() {
            #expect(message.sequenceNumber == index)
        }
    }

    @Test("Concurrent transcript updates are handled correctly")
    func testConcurrentTranscriptUpdates() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        // Create multiple pending messages
        var ids: [String] = []
        for i in 0..<5 {
            let id = await queue.enqueue(
                role: .user,
                audioData: Data([UInt8(i)]),
                transcriptStatus: .inProgress
            )
            ids.append(id)
        }

        // Update all transcripts concurrently
        await withTaskGroup(of: Void.self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    await queue.updateTranscript(id: id, transcript: "Transcript \(index)")
                }
            }
        }

        let messages = await queue.getOrderedMessages()
        #expect(messages.count == 5)

        // Verify all messages have correct transcripts
        for (index, message) in messages.enumerated() {
            #expect(message.text == "Transcript \(index)")
        }
    }

    // MARK: - Audio Data Tests

    @Test("Audio data is preserved in messages")
    func testAudioDataPreservation() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())
        let audioData = Data([1, 2, 3, 4, 5])

        let userId = await queue.enqueue(
            role: .user,
            audioData: audioData,
            transcriptStatus: .inProgress
        )

        await queue.updateTranscript(id: userId, transcript: "Test")

        let messages = await queue.getOrderedMessages()
        #expect(messages[0].audioData == audioData)
    }

    @Test("Messages without audio have nil audioData")
    func testNilAudioData() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(role: .user, text: "Text only")

        let messages = await queue.getOrderedMessages()
        #expect(messages[0].audioData == nil)
    }

    // MARK: - Queue Management Tests

    @Test("Clear removes all messages")
    func testClear() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(role: .user, text: "Message 1")
        await queue.enqueue(role: .assistant, text: "Message 2")
        await queue.enqueue(
            role: .user,
            audioData: Data([1]),
            transcriptStatus: .inProgress
        )

        await queue.clear()

        let messages = await queue.getOrderedMessages()
        let pending = await queue.pendingCount()
        let completed = await queue.completedCount()

        #expect(messages.isEmpty)
        #expect(pending == 0)
        #expect(completed == 0)
    }

    @Test("Sequence numbers restart after clear")
    func testSequenceNumbersRestartAfterClear() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(role: .user, text: "First batch")
        await queue.enqueue(role: .user, text: "First batch 2")

        await queue.clear()

        await queue.enqueue(role: .user, text: "Second batch")

        let messages = await queue.getOrderedMessages()
        #expect(messages.count == 1)
        #expect(messages[0].sequenceNumber == 0, "Sequence should restart at 0")
    }

    @Test("Pending and completed counts are accurate")
    func testCounts() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        let pending1 = await queue.pendingCount()
        let completed1 = await queue.completedCount()
        #expect(pending1 == 0)
        #expect(completed1 == 0)

        // Add completed message
        await queue.enqueue(role: .user, text: "Complete")

        let pending2 = await queue.pendingCount()
        let completed2 = await queue.completedCount()
        #expect(pending2 == 0)
        #expect(completed2 == 1)

        // Add pending message
        await queue.enqueue(
            role: .user,
            audioData: Data([1]),
            transcriptStatus: .inProgress
        )

        let pending3 = await queue.pendingCount()
        let completed3 = await queue.completedCount()
        #expect(pending3 == 1)
        #expect(completed3 == 1)
    }

    // MARK: - Edge Cases

    @Test("Empty transcript text is handled correctly")
    func testEmptyTranscript() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        let userId = await queue.enqueue(
            role: .user,
            audioData: Data([1]),
            transcriptStatus: .inProgress
        )

        await queue.updateTranscript(id: userId, transcript: "")

        let messages = await queue.getOrderedMessages()
        #expect(messages.count == 1)
        #expect(messages[0].text == "")
    }

    @Test("Updating non-existent message ID does nothing")
    func testUpdateNonExistentMessage() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(role: .user, text: "Real message")
        await queue.updateTranscript(id: "nonexistent-id", transcript: "Should not crash")

        let messages = await queue.getOrderedMessages()
        #expect(messages.count == 1)
        #expect(messages[0].text == "Real message")
    }

    @Test("Timestamps are set correctly")
    func testTimestamps() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())
        let beforeEnqueue = Date()

        await queue.enqueue(role: .user, text: "Test")

        let afterEnqueue = Date()
        let messages = await queue.getOrderedMessages()

        #expect(messages[0].timestamp >= beforeEnqueue)
        #expect(messages[0].timestamp <= afterEnqueue)
    }

    @Test("Message roles are preserved correctly")
    func testRolePreservation() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        await queue.enqueue(role: .user, text: "User message")
        await queue.enqueue(role: .assistant, text: "Assistant message")
        await queue.enqueue(role: .system, text: "System message")
        await queue.enqueue(role: .tool, text: "Tool message")

        let messages = await queue.getOrderedMessages()

        #expect(messages[0].role == .user)
        #expect(messages[1].role == .assistant)
        #expect(messages[2].role == .system)
        #expect(messages[3].role == .tool)
    }

    // MARK: - Complex Scenario Tests

    @Test("Complex conversation flow with mixed message types")
    func testComplexConversationFlow() async throws {
        let queue = MessageQueue(eventEmitter: EventEmitter())

        // User sends audio (pending transcript)
        let user1Id = await queue.enqueue(
            role: .user,
            audioData: Data([1, 2, 3]),
            transcriptStatus: .inProgress
        )

        // Assistant responds with text (before transcript completes)
        await queue.enqueue(
            role: .assistant,
            text: "I'm processing your request..."
        )

        // User sends another audio message
        let user2Id = await queue.enqueue(
            role: .user,
            audioData: Data([4, 5, 6]),
            transcriptStatus: .inProgress
        )

        // System message
        await queue.enqueue(
            role: .system,
            text: "Connection established"
        )

        // All pending
        var messages = await queue.getOrderedMessages()
        #expect(messages.isEmpty)

        // First transcript completes
        await queue.updateTranscript(id: user1Id, transcript: "Hello assistant")

        // First TWO messages finalize (user1 and assistant1)
        // user2 and system messages still pending (user2 blocks system)
        messages = await queue.getOrderedMessages()
        #expect(messages.count == 2)
        #expect(messages[0].text == "Hello assistant")
        #expect(messages[1].text == "I'm processing your request...")

        // Second transcript completes
        await queue.updateTranscript(id: user2Id, transcript: "Can you help me?")

        // All finalize
        messages = await queue.getOrderedMessages()
        #expect(messages.count == 4)
        #expect(messages[2].text == "Can you help me?")
        #expect(messages[3].text == "Connection established")
    }
}
