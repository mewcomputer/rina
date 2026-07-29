import Combine
import Foundation
import FoundationModels

protocol ConversationTitleGenerating: Sendable {
    func generateTitle(for prompt: String, answer: String) async -> String?
}

struct AppleIntelligenceTitleGenerator: ConversationTitleGenerating {
    func generateTitle(for prompt: String, answer: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let session = LanguageModelSession(instructions: """
            Create a concise title for a conversation. Use the first user message and the assistant's answer.
            Do not simply restate or re-ask the user's question. Focus the title on the underlying topic or task.
            Return only the title, with no explanation, quotes, prefix, or punctuation.
            Aim for four words. Never exceed eight words. If the title uses unusually long words, keep it to six words or fewer. Preserve the language of the conversation.
            """)
        let request = """
        First user message:
        \(Self.clipped(prompt))

        Assistant answer:
        \(Self.clipped(answer))
        """

        do {
            let response = try await session.respond(to: request)
            return ConversationTitleFormatter.sanitize(response.content)
        } catch {
            return nil
        }
    }

    private static func clipped(_ text: String) -> String {
        let limit = 4_000
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}

enum ConversationTitleFormatter {
    static func sanitize(_ rawTitle: String) -> String? {
        var title = rawTitle
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        title = title.replacingOccurrences(of: "**", with: "")
        title = title.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`"))
        )

        while title.first == "#" {
            title.removeFirst()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for marker in ["- ", "* ", "• "] where title.hasPrefix(marker) {
            title = String(title.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        title = title.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`"))
        )

        if title.lowercased().hasPrefix("title:") {
            title = String(title.dropFirst("title:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        }

        let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }

        let longWordThreshold = 10
        let hasLongWord = words.prefix(4).contains { word in
            word.filter(\.isLetter).count >= longWordThreshold
        }
        let maxWordCount = hasLongWord ? 6 : 8
        let limitedTitle = words.prefix(maxWordCount).joined(separator: " ")
        return limitedTitle.isEmpty ? nil : limitedTitle
    }
}

@MainActor
final class SessionHistoryStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published private(set) var persistenceError: String?

    private let repository: ConversationRepository
    private let titleGenerator: any ConversationTitleGenerating
    private var titleGenerationIDs: Set<ConversationID> = []

    init(
        repository: ConversationRepository,
        defaults: UserDefaults = .standard,
        titleGenerator: any ConversationTitleGenerating = AppleIntelligenceTitleGenerator()
    ) {
        self.repository = repository
        self.titleGenerator = titleGenerator
        self.conversations = []
        self.persistenceError = nil

        do {
            _ = try repository.importLegacy(from: defaults)
            _ = try repository.recoverInterruptedConversations()
            self.conversations = try repository.fetch()
        } catch {
            self.persistenceError = error.localizedDescription
        }
    }

    func refresh() {
        do {
            conversations = try repository.fetch()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func save(_ conversation: Conversation) {
        guard !conversation.messages.isEmpty else { return }

        do {
            try repository.upsert(conversation)
            conversations = try repository.fetch()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func remove(_ conversation: Conversation) {
        do {
            try repository.delete(conversation)
            conversations = try repository.fetch()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func title(for conversation: Conversation) -> String {
        if let title = conversation.title, !title.isEmpty {
            return title
        }

        let prompt = conversation.messages.first(where: { $0.role == .user })?
            .blocks
            .map(\.payload)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let prompt, !prompt.isEmpty else { return "New conversation" }
        return prompt.count > 48 ? String(prompt.prefix(48)) + "…" : prompt
    }

    func generateTitle(for conversation: Conversation) async {
        guard conversation.title == nil,
              let prompt = Self.firstUserMessage(in: conversation),
              let answer = Self.firstAssistantAnswer(in: conversation),
              titleGenerationIDs.insert(conversation.id).inserted
        else {
            return
        }
        defer { titleGenerationIDs.remove(conversation.id) }

        guard let generatedTitle = await titleGenerator.generateTitle(
            for: prompt,
            answer: answer
        ),
        let title = ConversationTitleFormatter.sanitize(generatedTitle),
        conversations.contains(where: { $0.id == conversation.id })
        else {
            return
        }

        guard var updated = conversations.first(where: { $0.id == conversation.id }) else {
            return
        }
        guard updated.title == nil else { return }
        updated.setTitle(title)
        do {
            try repository.upsert(updated)
            conversations = try repository.fetch()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func preview(for conversation: Conversation) -> String {
        conversation.messages.last?.blocks.map(\.payload).joined() ?? "No messages yet"
    }

    private static func firstUserMessage(in conversation: Conversation) -> String? {
        let prompt = conversation.messages
            .first(where: { $0.role == .user })?
            .blocks
            .filter { $0.kind == .text }
            .map(\.payload)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prompt, !prompt.isEmpty else { return nil }
        return prompt
    }

    private static func firstAssistantAnswer(in conversation: Conversation) -> String? {
        conversation.messages
            .filter { $0.role == .assistant }
            .map { message in
                message.blocks
                    .filter { $0.kind == .text }
                    .map(\.payload)
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty }
    }

}
