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

    func testConversationRoundTripPreservesContinuationAndToolBlocks() throws {
        let continuation = ProviderContinuation(
            provider: .umans,
            id: "block-0",
            kind: "reasoning",
            fields: ["thinking": "plan", "signature": "opaque"]
        )
        let conversation = Conversation(
            messages: [
                Message(
                    role: .assistant,
                    blocks: [
                        .toolCall(
                            callID: "call-1",
                            name: "current_time",
                            arguments: "{}",
                            isComplete: true
                        )
                    ],
                    providerContinuations: [continuation]
                )
            ]
        )

        let data = try JSONEncoder().encode(conversation)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded, conversation)
    }

    func testArtefactReferenceBlockRoundTripsStableIdentity() throws {
        let artefactID = ArtefactID()
        let revisionID = RevisionID()
        let block = ContentBlock.artefactReference(
            artefactID: artefactID,
            revisionID: revisionID,
            presentation: .inline
        )

        let decoded = try JSONDecoder().decode(
            ContentBlock.self,
            from: JSONEncoder().encode(block)
        )

        XCTAssertEqual(decoded, block)
        XCTAssertEqual(decoded.kind, .artefactReference)
        XCTAssertEqual(decoded.attributes["artefactID"], artefactID.rawValue.uuidString)
        XCTAssertEqual(decoded.attributes["revisionID"], revisionID.rawValue.uuidString)
        XCTAssertEqual(decoded.attributes["presentation"], "inline")
    }

    func testToolActivityGroupPairsCallsAndResultsByCallID() {
        let firstCall = ContentBlock.toolCall(
            callID: "call-1",
            name: "read",
            arguments: "{}",
            isComplete: true
        )
        let secondCall = ContentBlock.toolCall(
            callID: "call-2",
            name: "shell",
            arguments: "pwd",
            isComplete: true
        )
        let firstResult = ContentBlock.toolResult(
            callID: "call-1",
            result: "file contents"
        )
        let secondResult = ContentBlock.toolResult(
            callID: "call-2",
            result: "/workspace"
        )

        let group = ToolActivityGroup(
            calls: [firstCall, secondCall],
            results: [secondResult, firstResult]
        )

        XCTAssertEqual(group.activities.map { $0.call.attributes["callID"] }, ["call-1", "call-2"])
        XCTAssertEqual(group.activities.map { $0.result?.payload }, ["file contents", "/workspace"])
        XCTAssertTrue(group.unmatchedResults.isEmpty)
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
