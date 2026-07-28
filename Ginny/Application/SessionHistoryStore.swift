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
            Use no more than three long words or four short words. Preserve the language of the conversation.
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
        let maxWordCount = hasLongWord ? 3 : 4
        let limitedTitle = words.prefix(maxWordCount).joined(separator: " ")
        return limitedTitle.isEmpty ? nil : limitedTitle
    }
}

@MainActor
final class SessionHistoryStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]

    private let defaults: UserDefaults
    private let storageKey = "session.history"
    private let titleGenerator: any ConversationTitleGenerating
    private var titleGenerationIDs: Set<ConversationID> = []

    init(
        defaults: UserDefaults = .standard,
        titleGenerator: any ConversationTitleGenerating = AppleIntelligenceTitleGenerator()
    ) {
        self.defaults = defaults
        self.titleGenerator = titleGenerator
        if let data = defaults.data(forKey: storageKey),
           let conversations = try? JSONDecoder().decode([Conversation].self, from: data)
        {
            self.conversations = conversations.sorted { Self.lastActivity(of: $0) > Self.lastActivity(of: $1) }
        } else {
            self.conversations = []
        }
    }

    func save(_ conversation: Conversation) {
        guard !conversation.messages.isEmpty else { return }

        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
        conversations = Array(conversations.prefix(40))
        persist()
    }

    func remove(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        persist()
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
        let index = conversations.firstIndex(where: { $0.id == conversation.id })
        else {
            return
        }

        var updated = conversations[index]
        guard updated.title == nil else { return }
        updated.setTitle(title)
        conversations[index] = updated
        persist()
    }

    func preview(for conversation: Conversation) -> String {
        conversation.messages.last?.blocks.map(\.payload).joined() ?? "No messages yet"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        defaults.set(data, forKey: storageKey)
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

    private static func lastActivity(of conversation: Conversation) -> Date {
        conversation.messages.last?.createdAt ?? conversation.createdAt
    }
}
