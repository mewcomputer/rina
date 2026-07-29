import XCTest
@testable import Ginny

@MainActor
final class SessionHistoryTests: XCTestCase {
    func testSavingConversationAddsNewestConversationAndDerivesTitle() {
        let suiteName = "SessionHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let history = SessionHistoryStore(
            repository: try! ConversationRepository(isStoredInMemoryOnly: true),
            defaults: defaults
        )
        let conversation = Conversation(
            createdAt: Date(timeIntervalSince1970: 100),
            messages: [Message.user("Plan a quiet weekend"), Message.assistant("Start with one small ritual.")],
            generationState: .completed
        )

        history.save(conversation)

        XCTAssertEqual(history.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(history.title(for: conversation), "Plan a quiet weekend")
        XCTAssertEqual(history.preview(for: conversation), "Start with one small ritual.")
    }

    func testSavingSameConversationUpdatesItInsteadOfDuplicatingIt() {
        let suiteName = "SessionHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let history = SessionHistoryStore(
            repository: try! ConversationRepository(isStoredInMemoryOnly: true),
            defaults: defaults
        )
        let id = ConversationID()
        let first = Conversation(
            id: id,
            messages: [Message.user("First title")],
            generationState: .completed
        )
        let updated = Conversation(
            id: id,
            messages: [Message.user("Updated title"), Message.assistant("Updated answer")],
            generationState: .completed
        )

        history.save(first)
        history.save(updated)

        XCTAssertEqual(history.conversations.count, 1)
        XCTAssertEqual(history.title(for: history.conversations[0]), "Updated title")
    }

    func testGeneratingTitleUsesTheFirstMessageAndAnswerAndPersistsIt() async {
        let suiteName = "SessionHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let generator = TestConversationTitleGenerator(title: "Weekend Reset")
        let repository = try! ConversationRepository(isStoredInMemoryOnly: true)
        let history = SessionHistoryStore(
            repository: repository,
            defaults: defaults,
            titleGenerator: generator
        )
        let conversation = Conversation(
            messages: [
                Message.user("Help me plan a quiet weekend"),
                Message.assistant("Start with one small ritual and leave room for rest.")
            ],
            generationState: .completed
        )

        history.save(conversation)
        await history.generateTitle(for: conversation)

        XCTAssertEqual(history.title(for: history.conversations[0]), "Weekend Reset")
        XCTAssertEqual(generator.prompt, "Help me plan a quiet weekend")
        XCTAssertEqual(
            generator.answer,
            "Start with one small ritual and leave room for rest."
        )

        let restored = SessionHistoryStore(
            repository: repository,
            defaults: defaults,
            titleGenerator: generator
        )
        XCTAssertEqual(restored.title(for: restored.conversations[0]), "Weekend Reset")
    }

    func testTitleFormatterAimsForFourWordsWithSixOrEightWordCap() {
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("One two three four five six seven eight nine"),
            "One two three four five six seven eight"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize(
                "Conversation Endpoint Configuration Details Planning Review Archive"
            ),
            "Conversation Endpoint Configuration Details Planning Review"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("Title: \"One two\""),
            "One two"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("### \"One two\""),
            "One two"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("- One two"),
            "One two"
        )
    }

    func testConversationRepositoryRoundTripsConversationData() throws {
        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        var conversation = Conversation(
            createdAt: Date(timeIntervalSince1970: 100),
            title: "A saved session",
            messages: [
                Message.user("Hello"),
                Message(
                    role: .assistant,
                    blocks: [
                        .text("Partial answer", isComplete: false),
                        .toolCall(
                            callID: "call-1",
                            name: "current_time",
                            arguments: "{}"
                        )
                    ],
                    providerContinuations: [
                        ProviderContinuation(
                            provider: .umans,
                            id: "thinking-1",
                            kind: "reasoning",
                            fields: ["thinking": "plan"]
                        )
                    ]
                )
            ],
            generationState: .streaming
        )

        try repository.upsert(conversation)

        let restored = try XCTUnwrap(try repository.fetch().first)
        XCTAssertEqual(restored, conversation)

        conversation.setTitle("Renamed session")
        try repository.upsert(conversation)

        XCTAssertEqual(try repository.fetch().first?.title, "Renamed session")
        XCTAssertEqual(try repository.fetch().count, 1)
    }

    func testConversationRepositoryImportsLegacyUserDefaultsFixture() throws {
        let suiteName = "SessionHistoryTests.LegacyMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyConversation = Conversation(
            messages: [Message.user("Legacy prompt"), Message.assistant("Legacy answer")],
            generationState: .completed
        )
        defaults.set(
            try JSONEncoder().encode([legacyConversation]),
            forKey: "session.history"
        )

        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        let importedCount = try repository.importLegacy(from: defaults)

        XCTAssertEqual(importedCount, 1)
        XCTAssertNil(defaults.data(forKey: "session.history"))
        XCTAssertEqual(try repository.fetch(), [legacyConversation])
    }

    func testConversationRepositoryMigratesLegacyStructuredBlocksWithoutAttributes() throws {
        let suiteName = "SessionHistoryTests.LegacyStructuredBlock-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyConversation = Conversation(
            messages: [Message(
                role: .assistant,
                blocks: [.citationGroup("[]")]
            )],
            generationState: .completed
        )
        var fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode([legacyConversation])
            ) as? [[String: Any]]
        )
        var messages = try XCTUnwrap(fixture[0]["messages"] as? [[String: Any]])
        var blocks = try XCTUnwrap(messages[0]["blocks"] as? [[String: Any]])
        blocks[0].removeValue(forKey: "attributes")
        messages[0]["blocks"] = blocks
        fixture[0]["messages"] = messages
        defaults.set(
            try JSONSerialization.data(withJSONObject: fixture),
            forKey: "session.history"
        )

        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        XCTAssertEqual(try repository.importLegacy(from: defaults), 1)

        let restored = try XCTUnwrap(try repository.fetch().first)
        XCTAssertEqual(restored.messages[0].blocks[0].kind, .citationGroup)
        XCTAssertEqual(restored.messages[0].blocks[0].attributes, [:])
    }

    func testSessionHistoryRecoversInterruptedGeneration() throws {
        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        let conversation = Conversation(
            messages: [
                Message.user("Continue this"),
                Message.assistant("Partial answer", createdAt: Date(timeIntervalSince1970: 2))
            ],
            generationState: .streaming
        )
        try repository.upsert(conversation)

        let history = SessionHistoryStore(repository: repository)

        XCTAssertEqual(history.conversations.first?.generationState, .cancelled)
        XCTAssertEqual(
            history.conversations.first?.messages.last?.blocks.first?.payload,
            "Partial answer"
        )
    }
}

private final class TestConversationTitleGenerator: ConversationTitleGenerating, @unchecked Sendable {
    let title: String?
    var prompt = ""
    var answer = ""

    init(title: String?) {
        self.title = title
    }

    func generateTitle(for prompt: String, answer: String) async -> String? {
        self.prompt = prompt
        self.answer = answer
        return title
    }
}
