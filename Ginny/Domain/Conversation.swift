import Foundation

enum MessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
    case tool
}

enum ContentBlockKind: String, Codable, Equatable, Sendable {
    case text
}

struct ContentBlock: Codable, Equatable, Sendable {
    let id: ContentBlockID
    let kind: ContentBlockKind
    var payload: String
    var isComplete: Bool

    static func text(
        id: ContentBlockID = ContentBlockID(),
        _ payload: String,
        isComplete: Bool = true
    ) -> ContentBlock {
        ContentBlock(id: id, kind: .text, payload: payload, isComplete: isComplete)
    }
}

struct Message: Codable, Equatable, Sendable {
    let id: MessageID
    let role: MessageRole
    var blocks: [ContentBlock]
    let createdAt: Date

    init(
        id: MessageID = MessageID(),
        role: MessageRole,
        blocks: [ContentBlock],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.createdAt = createdAt
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
    private(set) var messages: [Message]
    private(set) var generationState: GenerationState

    init(
        id: ConversationID = ConversationID(),
        createdAt: Date = Date(),
        messages: [Message] = [],
        generationState: GenerationState = .idle
    ) {
        self.id = id
        self.createdAt = createdAt
        self.messages = messages
        self.generationState = generationState
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
