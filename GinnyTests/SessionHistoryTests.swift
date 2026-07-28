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
}
