import Foundation

struct ConversationID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
