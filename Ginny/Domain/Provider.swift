import Foundation

enum ProviderID: String, CaseIterable, Codable, Equatable, Sendable {
    case umans
    case kimi
    case kimiCode
    case openAICompatible

    var displayName: String {
        switch self {
        case .umans:
            "Umans"
        case .kimi:
            "Kimi"
        case .kimiCode:
            "Kimi Code"
        case .openAICompatible:
            "OpenAI-compatible"
        }
    }
}

enum ThinkingLevel: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case off
    case on
    case low
    case high
    case max

    var displayName: String {
        rawValue.capitalized
    }
}

enum ProviderMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
    case tool
}

struct ProviderContinuation: Codable, Equatable, Sendable {
    let provider: ProviderID
    let id: String
    let kind: String
    var fields: [String: String]
}

struct ProviderContinuationDelta: Equatable, Sendable {
    enum Operation: Equatable, Sendable {
        case append
        case replace
    }

    let provider: ProviderID
    let id: String
    let kind: String
    let field: String
    let value: String
    let operation: Operation
}

struct ProviderToolDefinition: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let inputSchema: String
}

struct ProviderToolCall: Codable, Equatable, Sendable {
    let id: String
    let name: String
    var arguments: String
    var isComplete: Bool
}

struct ProviderToolCallDelta: Equatable, Sendable {
    let provider: ProviderID
    let id: String
    let name: String?
    let arguments: String?
}

struct ProviderMessage: Codable, Equatable, Sendable {
    let role: ProviderMessageRole
    let content: String
    let continuations: [ProviderContinuation]
    let toolCalls: [ProviderToolCall]
    let toolCallID: String?

    init(
        role: ProviderMessageRole,
        content: String,
        continuations: [ProviderContinuation] = [],
        toolCalls: [ProviderToolCall] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.continuations = continuations
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    static func user(_ content: String) -> ProviderMessage {
        ProviderMessage(role: .user, content: content)
    }

    static func assistant(
        _ content: String,
        continuations: [ProviderContinuation] = [],
        toolCalls: [ProviderToolCall] = []
    ) -> ProviderMessage {
        ProviderMessage(
            role: .assistant,
            content: content,
            continuations: continuations,
            toolCalls: toolCalls
        )
    }

    static func system(_ content: String) -> ProviderMessage {
        ProviderMessage(role: .system, content: content)
    }

    static func tool(_ content: String, callID: String) -> ProviderMessage {
        ProviderMessage(role: .tool, content: content, toolCallID: callID)
    }
}

struct ProviderRequest: Equatable, Sendable {
    let messages: [ProviderMessage]
    let tools: [ProviderToolDefinition]

    init(messages: [ProviderMessage], tools: [ProviderToolDefinition] = []) {
        self.messages = messages
        self.tools = tools
    }
}

struct ProviderConfiguration: Codable, Equatable, Sendable {
    var provider: ProviderID
    var endpoint: URL
    var model: String
    var credentialID: String
    var thinkingLevel: ThinkingLevel?

    init(endpoint: URL, model: String, credentialID: String) {
        provider = .openAICompatible
        self.endpoint = endpoint
        self.model = model
        self.credentialID = credentialID
        thinkingLevel = nil
    }

    init(
        provider: ProviderID,
        endpoint: URL,
        model: String,
        credentialID: String,
        thinkingLevel: ThinkingLevel? = nil
    ) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.credentialID = credentialID
        self.thinkingLevel = thinkingLevel
    }
}

enum ProviderStreamEvent: Equatable, Sendable {
    case responseStarted
    case textDelta(String)
    case continuationDelta(ProviderContinuationDelta)
    case toolCallDelta(ProviderToolCallDelta)
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
    var supportsTools: Bool { get }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}
