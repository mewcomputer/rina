import Combine
import Foundation

@MainActor
final class SessionHistoryStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]

    private let defaults: UserDefaults
    private let storageKey = "session.history"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        let prompt = conversation.messages.first(where: { $0.role == .user })?
            .blocks
            .map(\.payload)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let prompt, !prompt.isEmpty else { return "New conversation" }
        return prompt.count > 48 ? String(prompt.prefix(48)) + "…" : prompt
    }

    func preview(for conversation: Conversation) -> String {
        conversation.messages.last?.blocks.map(\.payload).joined() ?? "No messages yet"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func lastActivity(of conversation: Conversation) -> Date {
        conversation.messages.last?.createdAt ?? conversation.createdAt
    }
}
