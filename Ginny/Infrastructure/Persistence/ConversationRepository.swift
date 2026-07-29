import Foundation
import SwiftData

enum ConversationPersistenceError: Error, Equatable {
    case invalidConversationID
    case invalidGenerationState(String)
    case invalidMessageID
    case invalidMessageRole(String)
    case malformedPayload
}

@Model
final class ConversationRecord {
    @Attribute(.unique) var idValue: String
    var createdAt: Date
    var title: String?
    var generationStateRaw: String
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    var messageRecords: [MessageRecord]

    init(
        idValue: String,
        createdAt: Date,
        title: String?,
        generationStateRaw: String,
        updatedAt: Date,
        messageRecords: [MessageRecord] = []
    ) {
        self.idValue = idValue
        self.createdAt = createdAt
        self.title = title
        self.generationStateRaw = generationStateRaw
        self.updatedAt = updatedAt
        self.messageRecords = messageRecords
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var idValue: String
    var roleRaw: String
    var createdAt: Date
    var sortIndex: Int
    var blocksData: Data
    var continuationsData: Data

    var conversation: ConversationRecord?

    init(
        idValue: String,
        roleRaw: String,
        createdAt: Date,
        sortIndex: Int,
        blocksData: Data,
        continuationsData: Data
    ) {
        self.idValue = idValue
        self.roleRaw = roleRaw
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.blocksData = blocksData
        self.continuationsData = continuationsData
    }
}

@MainActor
enum GinnyPersistence {
    static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            ConversationRecord.self,
            MessageRecord.self,
            ArtefactRecord.self,
            ArtefactRevisionRecord.self,
            SkillRecord.self,
            SkillRevisionRecord.self,
            SourceRecord.self,
            RelationshipRecord.self,
            CitationRecord.self,
            ContextRecord.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}

@MainActor
final class ConversationRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema([
            ConversationRecord.self,
            MessageRecord.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        context = ModelContext(container)
    }

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
    }

    func fetch() throws -> [Conversation] {
        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\ConversationRecord.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(domainConversation(from:))
    }

    func upsert(_ conversation: Conversation) throws {
        let idValue = conversation.id.rawValue.uuidString
        let descriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        let record: ConversationRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = ConversationRecord(
                idValue: idValue,
                createdAt: conversation.createdAt,
                title: conversation.title,
                generationStateRaw: conversation.generationState.rawValue,
                updatedAt: lastActivity(of: conversation)
            )
            context.insert(record)
        }

        record.createdAt = conversation.createdAt
        record.title = conversation.title
        record.generationStateRaw = conversation.generationState.rawValue
        record.updatedAt = lastActivity(of: conversation)

        let expectedIDs = Set(conversation.messages.map { $0.id.rawValue.uuidString })
        for messageRecord in record.messageRecords
            where !expectedIDs.contains(messageRecord.idValue)
        {
            context.delete(messageRecord)
        }

        var messageRecords: [MessageRecord] = []
        for (sortIndex, message) in conversation.messages.enumerated() {
            let messageID = message.id.rawValue.uuidString
            let existing = record.messageRecords.first { $0.idValue == messageID }
            let messageRecord: MessageRecord
            if let existing {
                messageRecord = existing
            } else {
                messageRecord = MessageRecord(
                    idValue: messageID,
                    roleRaw: message.role.rawValue,
                    createdAt: message.createdAt,
                    sortIndex: sortIndex,
                    blocksData: try encoder.encode(message.blocks),
                    continuationsData: try encoder.encode(message.providerContinuations)
                )
                context.insert(messageRecord)
            }
            messageRecord.roleRaw = message.role.rawValue
            messageRecord.createdAt = message.createdAt
            messageRecord.sortIndex = sortIndex
            messageRecord.blocksData = try encoder.encode(message.blocks)
            messageRecord.continuationsData = try encoder.encode(message.providerContinuations)
            messageRecord.conversation = record
            messageRecords.append(messageRecord)
        }
        record.messageRecords = messageRecords

        try context.save()
    }

    func delete(_ conversation: Conversation) throws {
        let idValue = conversation.id.rawValue.uuidString
        let descriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    @discardableResult
    func recoverInterruptedConversations() throws -> Int {
        let interrupted = try fetch().filter {
            $0.generationState == .preparing || $0.generationState == .streaming
        }

        for var conversation in interrupted {
            try conversation.cancelGeneration()
            try upsert(conversation)
        }
        return interrupted.count
    }

    @discardableResult
    func importLegacy(
        from defaults: UserDefaults,
        key: String = "session.history"
    ) throws -> Int {
        guard let data = defaults.data(forKey: key) else { return 0 }
        let conversations = try decoder.decode([Conversation].self, from: data)

        for conversation in conversations {
            try upsert(conversation)
        }
        defaults.removeObject(forKey: key)
        return conversations.count
    }

    private func domainConversation(from record: ConversationRecord) throws -> Conversation {
        guard let id = UUID(uuidString: record.idValue) else {
            throw ConversationPersistenceError.invalidConversationID
        }
        guard let generationState = GenerationState(rawValue: record.generationStateRaw) else {
            throw ConversationPersistenceError.invalidGenerationState(record.generationStateRaw)
        }

        let messages = try record.messageRecords
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(domainMessage(from:))

        return Conversation(
            id: ConversationID(rawValue: id),
            createdAt: record.createdAt,
            title: record.title,
            messages: messages,
            generationState: generationState
        )
    }

    private func domainMessage(from record: MessageRecord) throws -> Message {
        guard let id = UUID(uuidString: record.idValue) else {
            throw ConversationPersistenceError.invalidMessageID
        }
        guard let role = MessageRole(rawValue: record.roleRaw) else {
            throw ConversationPersistenceError.invalidMessageRole(record.roleRaw)
        }

        do {
            return Message(
                id: MessageID(rawValue: id),
                role: role,
                blocks: try decoder.decode([ContentBlock].self, from: record.blocksData),
                providerContinuations: try decoder.decode(
                    [ProviderContinuation].self,
                    from: record.continuationsData
                ),
                createdAt: record.createdAt
            )
        } catch {
            throw ConversationPersistenceError.malformedPayload
        }
    }

    private func lastActivity(of conversation: Conversation) -> Date {
        conversation.messages.last?.createdAt ?? conversation.createdAt
    }
}
