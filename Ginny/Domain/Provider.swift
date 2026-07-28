import Foundation

enum ProviderMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
}

struct ProviderMessage: Codable, Equatable, Sendable {
    let role: ProviderMessageRole
    let content: String

    static func user(_ content: String) -> ProviderMessage {
        ProviderMessage(role: .user, content: content)
    }

    static func assistant(_ content: String) -> ProviderMessage {
        ProviderMessage(role: .assistant, content: content)
    }

    static func system(_ content: String) -> ProviderMessage {
        ProviderMessage(role: .system, content: content)
    }
}

struct ProviderRequest: Equatable, Sendable {
    let messages: [ProviderMessage]

    init(messages: [ProviderMessage]) {
        self.messages = messages
    }
}

struct ProviderConfiguration: Codable, Equatable, Sendable {
    var endpoint: URL
    var model: String
    var credentialID: String

    init(endpoint: URL, model: String, credentialID: String) {
        self.endpoint = endpoint
        self.model = model
        self.credentialID = credentialID
    }
}

enum ProviderStreamEvent: Equatable, Sendable {
    case responseStarted
    case textDelta(String)
    case finish(reason: String?)
    case responseEnded
}

enum ProviderError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case missingCredential
    case invalidResponse
    case httpStatus(Int, message: String?)
    case malformedEvent
    case remote(message: String)
}

protocol ProviderAdapter: Sendable {
    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}
