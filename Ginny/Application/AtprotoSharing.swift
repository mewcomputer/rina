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
        guard string.count == 13,
              string.allSatisfy("234567abcdefghijklmnopqrstuvwxyz".contains)
        else {
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

struct RinaRecordMessage: Codable, Equatable, Sendable {
    let id: String
    let role: MessageRole
    let blocks: [RinaRecordBlock]
    let createdAt: String
}

struct RinaConversationSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let title: String
    let createdAt: String
    let updatedAt: String
    let messages: [RinaRecordMessage]
}

struct RinaArtefactSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
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
    case notAuthenticated
    case unsupportedCollection

    var errorDescription: String? {
        switch self {
        case .invalidRecordKey: "The atproto record key is invalid."
        case .missingCurrentRevision: "This artefact has no saved revision to publish."
        case .notAuthenticated: "Sign in to atproto before publishing."
        case .unsupportedCollection: "This atproto collection is not supported by Ginny."
        }
    }
}

enum AtprotoSnapshotBuilder {
    static func conversation(
        _ conversation: Conversation,
        now: Date = Date()
    ) -> RinaConversationSnapshot {
        RinaConversationSnapshot(
            schemaVersion: RinaConversationSnapshot.schemaVersion,
            title: conversation.title ?? "Untitled conversation",
            createdAt: timestamp(conversation.createdAt),
            updatedAt: timestamp(now),
            messages: conversation.messages.compactMap { message in
                let blocks = message.blocks.compactMap { block -> RinaRecordBlock? in
                    guard block.kind != .toolCall, block.kind != .toolResult else { return nil }
                    return RinaRecordBlock(
                        id: block.id.rawValue.uuidString,
                        kind: block.kind.rawValue,
                        payload: block.payload,
                        attributes: block.attributes.filter { key, _ in
                            key != "callID" && key != "approvalState"
                        }
                    )
                }
                guard !blocks.isEmpty else { return nil }
                return RinaRecordMessage(
                    id: message.id.rawValue.uuidString,
                    role: message.role,
                    blocks: blocks,
                    createdAt: timestamp(message.createdAt)
                )
            }
        )
    }

    static func artefact(
        _ artefact: Artefact,
        now: Date = Date()
    ) throws -> RinaArtefactSnapshot {
        guard let revision = artefact.currentRevision else {
            throw AtprotoSharingError.missingCurrentRevision
        }
        return RinaArtefactSnapshot(
            schemaVersion: RinaArtefactSnapshot.schemaVersion,
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
        let alphabet = Array("234567abcdefghijklmnopqrstuvwxyz")
        return "3" + String((0..<12).compactMap { _ in alphabet.randomElement() })
    }
}
