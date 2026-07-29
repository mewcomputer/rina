import Foundation

enum MessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
    case tool
}

enum ContentBlockKind: String, Codable, Equatable, Sendable {
    case text
    case toolCall
    case toolResult
    case artefactReference
}

enum ArtefactReferencePresentation: String, Codable, Equatable, Sendable {
    case card
    case inline
}

enum ToolApprovalState: String, Codable, Equatable, Sendable {
    case automatic
    case approved
    case denied
}

struct ContentBlock: Codable, Equatable, Sendable {
    let id: ContentBlockID
    let kind: ContentBlockKind
    var payload: String
    var attributes: [String: String]
    var isComplete: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case payload
        case attributes
        case isComplete
    }

    init(
        id: ContentBlockID,
        kind: ContentBlockKind,
        payload: String,
        attributes: [String: String] = [:],
        isComplete: Bool
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.attributes = attributes
        self.isComplete = isComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ContentBlockID.self, forKey: .id)
        kind = try container.decode(ContentBlockKind.self, forKey: .kind)
        payload = try container.decode(String.self, forKey: .payload)
        attributes = try container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
    }

    static func text(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        attributes: [String: String] = [:],
        isComplete: Bool = true
    ) -> ContentBlock {
        return ContentBlock(
            id: id,
            kind: .text,
            payload: payload,
            attributes: attributes,
            isComplete: isComplete
        )
    }

    static func toolCall(
        id: ContentBlockID = ContentBlockID(),
        callID: String,
        name: String,
        arguments: String = "",
        isComplete: Bool = false
    ) -> ContentBlock {
        ContentBlock(
            id: id,
            kind: .toolCall,
            payload: arguments,
            attributes: ["callID": callID, "name": name],
            isComplete: isComplete
        )
    }

    static func toolResult(
        id: ContentBlockID = ContentBlockID(),
        callID: String,
        result: String,
        isError: Bool = false,
        approvalState: ToolApprovalState? = nil
    ) -> ContentBlock {
        var attributes = ["callID": callID, "isError": String(isError)]
        if let approvalState {
            attributes["approvalState"] = approvalState.rawValue
        }
        return ContentBlock(
            id: id,
            kind: .toolResult,
            payload: result,
            attributes: attributes,
            isComplete: true
        )
    }

    static func artefactReference(
        id: ContentBlockID = ContentBlockID(),
        artefactID: ArtefactID,
        revisionID: RevisionID,
        presentation: ArtefactReferencePresentation
    ) -> ContentBlock {
        ContentBlock(
            id: id,
            kind: .artefactReference,
            payload: "",
            attributes: [
                "artefactID": artefactID.rawValue.uuidString,
                "revisionID": revisionID.rawValue.uuidString,
                "presentation": presentation.rawValue
            ],
            isComplete: true
        )
    }
}

struct ToolActivity: Equatable, Sendable, Identifiable {
    let call: ContentBlock
    let result: ContentBlock?

    var id: ContentBlockID {
        call.id
    }
}

struct ToolActivityGroup: Equatable, Sendable {
    let activities: [ToolActivity]
    let unmatchedResults: [ContentBlock]

    init(calls: [ContentBlock], results: [ContentBlock]) {
        var remainingResults = results
        var activities: [ToolActivity] = []

        for call in calls {
            let callID = call.attributes["callID"]
            let resultIndex = remainingResults.firstIndex {
                $0.attributes["callID"] == callID
            }
            let result = resultIndex.map { remainingResults.remove(at: $0) }
            activities.append(ToolActivity(call: call, result: result))
        }

        self.activities = activities
        unmatchedResults = remainingResults
    }
}

struct Message: Codable, Equatable, Sendable {
    let id: MessageID
    let role: MessageRole
    var blocks: [ContentBlock]
    var providerContinuations: [ProviderContinuation]
    let createdAt: Date

    init(
        id: MessageID = MessageID(),
        role: MessageRole,
        blocks: [ContentBlock],
        providerContinuations: [ProviderContinuation] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.providerContinuations = providerContinuations
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case blocks
        case providerContinuations
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(MessageID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        blocks = try container.decode([ContentBlock].self, forKey: .blocks)
        providerContinuations = try container.decodeIfPresent(
            [ProviderContinuation].self,
            forKey: .providerContinuations
        ) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    static func user(_ text: String, createdAt: Date = Date()) -> Message {
        Message(role: .user, blocks: [.text(text)], createdAt: createdAt)
    }

    static func assistant(_ text: String, createdAt: Date = Date()) -> Message {
        Message(role: .assistant, blocks: [.text(text)], createdAt: createdAt)
    }
}

enum GenerationState: String, Codable, Equatable, Sendable {
    case idle
    case preparing
    case streaming
    case completed
    case cancelled
    case failed
}

enum ConversationError: Error, Equatable, Sendable {
    case duplicateMessageID(MessageID)
    case messageNotFound(MessageID)
    case invalidGenerationTransition(from: GenerationState, to: GenerationState)
}

struct Conversation: Codable, Equatable, Sendable {
    let id: ConversationID
    let createdAt: Date
    private(set) var title: String?
    private(set) var messages: [Message]
    private(set) var generationState: GenerationState

    init(
        id: ConversationID = ConversationID(),
        createdAt: Date = Date(),
        title: String? = nil,
        messages: [Message] = [],
        generationState: GenerationState = .idle
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.messages = messages
        self.generationState = generationState
    }

    mutating func setTitle(_ title: String?) {
        self.title = title
    }

    mutating func appendMessage(_ message: Message) throws {
        guard !messages.contains(where: { $0.id == message.id }) else {
            throw ConversationError.duplicateMessageID(message.id)
        }

        messages.append(message)
    }

    mutating func updateMessage(_ message: Message) throws {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            throw ConversationError.messageNotFound(message.id)
        }

        messages[index] = message
    }

    mutating func beginGeneration() throws {
        try transition(to: .preparing, from: [.idle, .completed, .cancelled, .failed])
    }

    mutating func beginStreaming() throws {
        try transition(to: .streaming, from: [.preparing])
    }

    mutating func completeGeneration() throws {
        try transition(to: .completed, from: [.streaming])
    }

    mutating func cancelGeneration() throws {
        try transition(to: .cancelled, from: [.preparing, .streaming])
    }

    mutating func failGeneration() throws {
        try transition(to: .failed, from: [.preparing, .streaming])
    }

    private mutating func transition(
        to nextState: GenerationState,
        from validStates: Set<GenerationState>
    ) throws {
        guard validStates.contains(generationState) else {
            throw ConversationError.invalidGenerationTransition(
                from: generationState,
                to: nextState
            )
        }

        generationState = nextState
    }
}
