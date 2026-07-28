import XCTest
@testable import Ginny

@MainActor
final class SessionHistoryTests: XCTestCase {
    func testSavingConversationAddsNewestConversationAndDerivesTitle() {
        let suiteName = "SessionHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let history = SessionHistoryStore(defaults: defaults)
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

        let history = SessionHistoryStore(defaults: defaults)
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
        let history = SessionHistoryStore(defaults: defaults, titleGenerator: generator)
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

        let restored = SessionHistoryStore(defaults: defaults, titleGenerator: generator)
        XCTAssertEqual(restored.title(for: restored.conversations[0]), "Weekend Reset")
    }

    func testTitleFormatterKeepsFourShortWordsOrThreeLongWords() {
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("One two three four five"),
            "One two three four"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("Conversation Endpoint Configuration Details"),
            "Conversation Endpoint Configuration"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("Title: \"One two\""),
            "One two"
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
