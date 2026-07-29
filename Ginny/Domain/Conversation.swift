import Foundation

enum MessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
    case tool
}

enum ContentBlockKind: Codable, Equatable, Sendable {
    case text
    case markdown
    case code
    case table
    case mermaid
    case image
    case fileReference
    case citationGroup
    case toolCall
    case toolResult
    case artefactReference
    case providerNotice
    case unknown(String)

    var rawValue: String {
        switch self {
        case .text: "text"
        case .markdown: "markdown"
        case .code: "code"
        case .table: "table"
        case .mermaid: "mermaid"
        case .image: "image"
        case .fileReference: "fileReference"
        case .citationGroup: "citationGroup"
        case .toolCall: "toolCall"
        case .toolResult: "toolResult"
        case .artefactReference: "artefactReference"
        case .providerNotice: "providerNotice"
        case .unknown(let rawValue): rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "text": self = .text
        case "markdown": self = .markdown
        case "code": self = .code
        case "table": self = .table
        case "mermaid": self = .mermaid
        case "image": self = .image
        case "fileReference": self = .fileReference
        case "citationGroup": self = .citationGroup
        case "toolCall": self = .toolCall
        case "toolResult": self = .toolResult
        case "artefactReference": self = .artefactReference
        case "providerNotice": self = .providerNotice
        default: self = .unknown(rawValue)
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try String(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
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
    static let currentSchemaVersion = 1
    static let schemaVersionKey = "schemaVersion"

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

    static func markdown(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        isComplete: Bool = true
    ) -> ContentBlock {
        structured(
            id: id,
            kind: .markdown,
            payload: payload,
            isComplete: isComplete
        )
    }

    static func code(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        language: String? = nil,
        isComplete: Bool = true
    ) -> ContentBlock {
        var attributes: [String: String] = [:]
        if let language {
            attributes["language"] = language
        }
        return structured(
            id: id,
            kind: .code,
            payload: payload,
            attributes: attributes,
            isComplete: isComplete
        )
    }

    static func table(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        isComplete: Bool = true
    ) -> ContentBlock {
        structured(id: id, kind: .table, payload: payload, isComplete: isComplete)
    }

    static func mermaid(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        isComplete: Bool = true
    ) -> ContentBlock {
        structured(id: id, kind: .mermaid, payload: payload, isComplete: isComplete)
    }

    static func image(
        id: ContentBlockID = ContentBlockID(),
        reference: String,
        mimeType: String? = nil,
        alt: String? = nil,
        isComplete: Bool = true
    ) -> ContentBlock {
        var attributes: [String: String] = [:]
        if let mimeType { attributes["mimeType"] = mimeType }
        if let alt { attributes["alt"] = alt }
        return structured(
            id: id,
            kind: .image,
            payload: reference,
            attributes: attributes,
            isComplete: isComplete
        )
    }

    static func fileReference(
        id: ContentBlockID = ContentBlockID(),
        sourceID: SourceID,
        displayName: String,
        isComplete: Bool = true
    ) -> ContentBlock {
        structured(
            id: id,
            kind: .fileReference,
            payload: "",
            attributes: [
                "sourceID": sourceID.rawValue.uuidString,
                "displayName": displayName
            ],
            isComplete: isComplete
        )
    }

    static func citationGroup(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        isComplete: Bool = true
    ) -> ContentBlock {
        structured(id: id, kind: .citationGroup, payload: payload, isComplete: isComplete)
    }

    static func providerNotice(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        isComplete: Bool = true
    ) -> ContentBlock {
        structured(id: id, kind: .providerNotice, payload: payload, isComplete: isComplete)
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

    private static func structured(
        id: ContentBlockID,
        kind: ContentBlockKind,
        payload: String,
        attributes: [String: String] = [:],
        isComplete: Bool
    ) -> ContentBlock {
        var attributes = attributes
        attributes[schemaVersionKey] = String(currentSchemaVersion)
        return ContentBlock(
            id: id,
            kind: kind,
            payload: payload,
            attributes: attributes,
            isComplete: isComplete
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

struct ToolActivityCopy: Sendable {
    let inProgress: String
    let completed: String
    let failed: String
}

let toolActivityCopies: [String: ToolActivityCopy] = [
    "create_artefact": ToolActivityCopy(
        inProgress: "Writing artefact",
        completed: "Wrote artefact",
        failed: "Couldn’t write artefact"
    ),
    "update_artefact": ToolActivityCopy(
        inProgress: "Updating artefact",
        completed: "Updated artefact",
        failed: "Couldn’t update artefact"
    ),
    "read_artefact": ToolActivityCopy(
        inProgress: "Reading artefact",
        completed: "Read artefact",
        failed: "Couldn’t read artefact"
    ),
    "list_artefacts": ToolActivityCopy(
        inProgress: "Searching artefacts",
        completed: "Searched artefacts",
        failed: "Couldn’t search artefacts"
    ),
    "discover_skills": ToolActivityCopy(
        inProgress: "Finding skills",
        completed: "Found skills",
        failed: "Couldn’t find skills"
    ),
    "read_skill": ToolActivityCopy(
        inProgress: "Reading skill",
        completed: "Read skill",
        failed: "Couldn’t read skill"
    ),
    "current_time": ToolActivityCopy(
        inProgress: "Checking time",
        completed: "Checked time",
        failed: "Couldn’t check time"
    )
]

func toolActivityLabel(for group: ToolActivityGroup) -> String {
    guard group.activities.count == 1,
          let name = group.activities.first?.call.attributes["name"],
          let copy = toolActivityCopies[name]
    else {
        return group.activities.count == 1
            ? "Tool activity"
            : "\(group.activities.count) tool activities"
    }

    let isPending = group.activities.contains { !$0.call.isComplete || $0.result == nil }
    guard !isPending else { return copy.inProgress }

    let containsError = group.activities.contains {
        $0.result?.attributes["isError"] == "true"
    } || group.unmatchedResults.contains {
        $0.attributes["isError"] == "true"
    }
    return containsError ? copy.failed : copy.completed
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
