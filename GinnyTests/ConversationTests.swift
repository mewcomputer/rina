import XCTest
@testable import Ginny

final class ConversationTests: XCTestCase {
    func testConversationStartsEmptyAndPreservesIdentity() {
        let id = ConversationID()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let conversation = Conversation(id: id, createdAt: createdAt)

        XCTAssertEqual(conversation.id, id)
        XCTAssertEqual(conversation.createdAt, createdAt)
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertEqual(conversation.generationState, .idle)
    }

    func testMessagesRemainInInsertionOrder() throws {
        var conversation = Conversation()
        let first = Message.user("first")
        let second = Message.assistant("second")

        try conversation.appendMessage(first)
        try conversation.appendMessage(second)

        XCTAssertEqual(conversation.messages.map(\.id), [first.id, second.id])
    }

    func testDuplicateMessageIDsAreRejected() throws {
        var conversation = Conversation()
        let id = MessageID()
        let first = Message(id: id, role: .user, blocks: [.text("first")])
        let duplicate = Message(id: id, role: .assistant, blocks: [.text("duplicate")])

        try conversation.appendMessage(first)

        XCTAssertThrowsError(try conversation.appendMessage(duplicate)) { error in
            XCTAssertEqual(error as? ConversationError, .duplicateMessageID(id))
        }
    }

    func testMessageUpdatesPreserveStableIdentityAndSupportPartialContent() throws {
        var conversation = Conversation()
        let messageID = MessageID()
        let blockID = ContentBlockID()
        let partial = Message(
            id: messageID,
            role: .assistant,
            blocks: [.text(id: blockID, "partial", isComplete: false)]
        )
        try conversation.appendMessage(partial)

        let completed = Message(
            id: messageID,
            role: .assistant,
            blocks: [.text(id: blockID, "partial response", isComplete: true)]
        )
        try conversation.updateMessage(completed)

        XCTAssertEqual(conversation.messages[0].id, messageID)
        XCTAssertEqual(conversation.messages[0].blocks, completed.blocks)
    }

    func testGenerationFollowsTheDocumentedLifecycle() throws {
        var conversation = Conversation()

        try conversation.beginGeneration()
        XCTAssertEqual(conversation.generationState, .preparing)

        try conversation.beginStreaming()
        XCTAssertEqual(conversation.generationState, .streaming)

        try conversation.completeGeneration()
        XCTAssertEqual(conversation.generationState, .completed)
    }

    func testGenerationRejectsInvalidTransitions() throws {
        var conversation = Conversation()

        XCTAssertThrowsError(try conversation.beginStreaming()) { error in
            XCTAssertEqual(
                error as? ConversationError,
                .invalidGenerationTransition(from: .idle, to: .streaming)
            )
        }
    }

    func testCancellationAndFailureAreTerminalStates() throws {
        var cancelled = Conversation()
        try cancelled.beginGeneration()
        try cancelled.cancelGeneration()

        var failed = Conversation()
        try failed.beginGeneration()
        try failed.beginStreaming()
        try failed.failGeneration()

        XCTAssertEqual(cancelled.generationState, .cancelled)
        XCTAssertEqual(failed.generationState, .failed)
    }
}
