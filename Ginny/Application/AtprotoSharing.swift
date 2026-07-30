import AtprotoClient
import AtprotoTypes
import Foundation

enum AtprotoRecordCollection {
    static let conversation = "computer.mew.rina.conversation"
    static let artefact = "computer.mew.rina.artefact"
}

struct RinaRecordKey: Atproto.RecordKey, Codable, Equatable {
    let rawValue: String

    init(string: String) throws {
        guard (try? TID(string: string)) != nil else {
            throw AtprotoSharingError.invalidRecordKey
        }
        rawValue = string
    }
}

struct RinaCollection: Atproto.RecordType, Sendable {
    static let nsid = Atproto.NSID(string: AtprotoRecordCollection.conversation)
    init() {}
}

struct RinaArtefactCollection: Atproto.RecordType, Sendable {
    static let nsid = Atproto.NSID(string: AtprotoRecordCollection.artefact)
    init() {}
}

struct RinaRecordBlock: Codable, Equatable, Sendable {
    let id: String
    let kind: String
    let payload: String
    let attributes: [String: String]
}

struct RinaRecordContinuation: Codable, Equatable, Sendable {
    let provider: String
    let id: String
    let kind: String
    let fields: [String: String]
}

struct RinaRecordMessage: Codable, Equatable, Sendable {
    let id: String
    let role: MessageRole
    let blocks: [RinaRecordBlock]
    let providerContinuations: [RinaRecordContinuation]
    let createdAt: String

    init(
        id: String,
        role: MessageRole,
        blocks: [RinaRecordBlock],
        providerContinuations: [RinaRecordContinuation] = [],
        createdAt: String
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
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        blocks = try container.decode([RinaRecordBlock].self, forKey: .blocks)
        providerContinuations = try container.decodeIfPresent(
            [RinaRecordContinuation].self,
            forKey: .providerContinuations
        ) ?? []
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }
}

struct RinaArtefactReference: Codable, Equatable, Sendable {
    let id: String
    let revisionID: String
    let uri: String
}

struct RinaGenerationMetadata: Codable, Equatable, Sendable {
    let provider: String?
    let model: String?
    let thinkingLevel: String?

    init(
        provider: String? = nil,
        model: String? = nil,
        thinkingLevel: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.thinkingLevel = thinkingLevel
    }
}

struct RinaConversationSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let title: String
    let createdAt: String
    let updatedAt: String
    let generation: RinaGenerationMetadata?
    let messages: [RinaRecordMessage]
    let artefacts: [RinaArtefactReference]

    init(
        schemaVersion: Int,
        title: String,
        createdAt: String,
        updatedAt: String,
        generation: RinaGenerationMetadata? = nil,
        messages: [RinaRecordMessage],
        artefacts: [RinaArtefactReference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.generation = generation
        self.messages = messages
        self.artefacts = artefacts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case title
        case createdAt
        case updatedAt
        case generation
        case messages
        case artefacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        generation = try container.decodeIfPresent(RinaGenerationMetadata.self, forKey: .generation)
        messages = try container.decode([RinaRecordMessage].self, forKey: .messages)
        artefacts = try container.decodeIfPresent(
            [RinaArtefactReference].self,
            forKey: .artefacts
        ) ?? []
    }
}

struct RinaArtefactSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: String?
    let revisionID: String?
    let title: String
    let kind: ArtefactKind
    let createdAt: String
    let updatedAt: String
    let source: String
    let renderedContent: String?
    let metadata: [String: String]
}

struct RinaConversationRecord: Atproto.Record, Codable, Equatable, Sendable {
    typealias Collection = RinaCollection
    typealias Key = RinaRecordKey

    let nsid = RinaCollection()
    let snapshot: RinaConversationSnapshot

    enum CodingKeys: String, CodingKey {
        case nsid = "$type"
        case snapshot
    }
}

struct RinaArtefactRecord: Atproto.Record, Codable, Equatable, Sendable {
    typealias Collection = RinaArtefactCollection
    typealias Key = RinaRecordKey

    let nsid = RinaArtefactCollection()
    let snapshot: RinaArtefactSnapshot

    enum CodingKeys: String, CodingKey {
        case nsid = "$type"
        case snapshot
    }
}

struct AtprotoPublication: Codable, Equatable, Sendable, Identifiable {
    static let publicWebBaseURL = URL(string: "https://rina.mew.computer")!

    let collection: String
    let rkey: String
    let uri: String
    let updatedAt: Date
    let subjectID: String?

    var id: String { "\(collection):\(rkey)" }

    var publicWebURL: URL? {
        let parts = uri.dropFirst("at://".count).split(separator: "/")
        guard parts.count == 3,
              parts[1] == Substring(collection) else { return nil }
        return URL(
            string: "\(Self.publicWebBaseURL)/s/\(parts[0])/\(collection)/\(parts[2])"
        )
    }
}

enum AtprotoSharingError: Error, Equatable, LocalizedError, Sendable {
    case invalidRecordKey
    case missingCurrentRevision
    case missingReferencedArtefact(ArtefactID)
    case missingReferencedRevision(ArtefactID, RevisionID)
    case notAuthenticated
    case unsupportedCollection

    var errorDescription: String? {
        switch self {
        case .invalidRecordKey: "The atproto record key is invalid."
        case .missingCurrentRevision: "This artefact has no saved revision to publish."
        case .missingReferencedArtefact(let id):
            "The referenced artefact \(id.rawValue.rawValue) is not available locally."
        case .missingReferencedRevision(let artefactID, let revisionID):
            "The referenced revision \(revisionID.rawValue.rawValue) for artefact \(artefactID.rawValue.rawValue) is not available locally."
        case .notAuthenticated: "Sign in to atproto before publishing."
        case .unsupportedCollection: "This atproto collection is not supported by Ginny."
        }
    }
}

enum AtprotoSnapshotBuilder {
    static func conversation(
        _ conversation: Conversation,
        artefactReferences: [RinaArtefactReference] = [],
        generation: RinaGenerationMetadata? = nil,
        now: Date = Date()
    ) -> RinaConversationSnapshot {
        RinaConversationSnapshot(
            schemaVersion: RinaConversationSnapshot.schemaVersion,
            title: conversation.title ?? "Untitled conversation",
            createdAt: timestamp(conversation.createdAt),
            updatedAt: timestamp(now),
            generation: generation,
            messages: conversation.messages.compactMap { message in
                let blocks = message.blocks.map { block in
                    RinaRecordBlock(
                        id: block.id.rawValue.rawValue,
                        kind: block.kind.rawValue,
                        payload: block.payload,
                        attributes: block.attributes
                    )
                }
                guard !blocks.isEmpty || !message.providerContinuations.isEmpty else {
                    return nil
                }
                return RinaRecordMessage(
                    id: message.id.rawValue.rawValue,
                    role: message.role,
                    blocks: blocks,
                    providerContinuations: message.providerContinuations.map {
                        RinaRecordContinuation(
                            provider: $0.provider.rawValue,
                            id: $0.id,
                            kind: $0.kind,
                            fields: $0.fields
                        )
                    },
                    createdAt: timestamp(message.createdAt)
                )
            },
            artefacts: artefactReferences
        )
    }

    static func artefact(
        _ artefact: Artefact,
        revisionID: RevisionID? = nil,
        now: Date = Date()
    ) throws -> RinaArtefactSnapshot {
        let revision: ArtefactRevision
        if let revisionID {
            guard let requestedRevision = artefact.revision(id: revisionID) else {
                throw AtprotoSharingError.missingReferencedRevision(artefact.id, revisionID)
            }
            revision = requestedRevision
        } else {
            guard let currentRevision = artefact.currentRevision else {
                throw AtprotoSharingError.missingCurrentRevision
            }
            revision = currentRevision
        }
        return RinaArtefactSnapshot(
            schemaVersion: RinaArtefactSnapshot.schemaVersion,
            id: artefact.id.rawValue.rawValue,
            revisionID: revision.id.rawValue.rawValue,
            title: artefact.title,
            kind: artefact.kind,
            createdAt: timestamp(artefact.createdAt),
            updatedAt: timestamp(now),
            source: revision.source,
            renderedContent: revision.renderedContent,
            metadata: revision.metadata
        )
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

@MainActor
final class AtprotoPublicationStore: ObservableObject {
    @Published private(set) var publications: [AtprotoPublication]

    private let defaults: UserDefaults
    private let key = "atproto.publications"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        publications = (try? Self.decode(defaults.data(forKey: key))) ?? []
    }

    func publication(collection: String, rkey: String) -> AtprotoPublication? {
        publications.first { $0.collection == collection && $0.rkey == rkey }
    }

    func save(_ publication: AtprotoPublication) {
        publications.removeAll { $0.id == publication.id }
        publications.append(publication)
        persist()
    }

    func remove(collection: String, rkey: String) {
        publications.removeAll { $0.collection == collection && $0.rkey == rkey }
        persist()
    }

    func removeAll() {
        publications.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(publications), forKey: key)
    }

    private static func decode(_ data: Data?) throws -> [AtprotoPublication] {
        guard let data else { return [] }
        return try JSONDecoder().decode([AtprotoPublication].self, from: data)
    }
}

actor AtprotoSharingService {
    private let authService: AtprotoAuthService

    init(authService: AtprotoAuthService) {
        self.authService = authService
    }

    func publish(
        _ snapshot: RinaConversationSnapshot,
        publication: AtprotoPublication? = nil,
        subjectID: String
    ) async throws -> AtprotoPublication {
        let record = RinaConversationRecord(snapshot: snapshot)
        return try await publishRecord(
            record,
            collection: AtprotoRecordCollection.conversation,
            publication: publication,
            subjectID: subjectID
        )
    }

    func publish(
        _ snapshot: RinaArtefactSnapshot,
        publication: AtprotoPublication? = nil,
        subjectID: String
    ) async throws -> AtprotoPublication {
        let record = RinaArtefactRecord(snapshot: snapshot)
        return try await publishRecord(
            record,
            collection: AtprotoRecordCollection.artefact,
            publication: publication,
            subjectID: subjectID
        )
    }

    func delete(_ publication: AtprotoPublication) async throws {
        switch publication.collection {
        case AtprotoRecordCollection.conversation:
            try await authService.deleteRecord(
                type: RinaConversationRecord.self,
                rkey: try RinaRecordKey(string: publication.rkey)
            )
        case AtprotoRecordCollection.artefact:
            try await authService.deleteRecord(
                type: RinaArtefactRecord.self,
                rkey: try RinaRecordKey(string: publication.rkey)
            )
        default:
            throw AtprotoSharingError.unsupportedCollection
        }
    }

    private func publishRecord<R: Atproto.Record>(
        _ record: R,
        collection: String,
        publication: AtprotoPublication?,
        subjectID: String
    ) async throws -> AtprotoPublication where R.Key == RinaRecordKey {
        if let publication, publication.collection != collection {
            throw AtprotoSharingError.unsupportedCollection
        }
        let key = try RinaRecordKey(string: publication?.rkey ?? Self.newRecordKey())
        let did = try await authService.authenticatedDID()
        if publication == nil {
            try await authService.createRecord(record, rkey: key)
        } else {
            try await authService.putRecord(record, rkey: key)
        }
        return AtprotoPublication(
            collection: collection,
            rkey: key.rawValue,
            uri: "at://\(did)/\(collection)/\(key.rawValue)",
            updatedAt: Date(),
            subjectID: subjectID
        )
    }

    private static func newRecordKey() -> String {
        TID().rawValue
    }
}
