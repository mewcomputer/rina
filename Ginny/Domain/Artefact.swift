import Foundation

enum ArtefactKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case document
    case code
    case web
    case inlineWeb
}

enum ArtefactError: Error, Equatable, Sendable {
    case revisionNotFound(RevisionID)
}

struct ArtefactRevision: Codable, Equatable, Identifiable, Sendable {
    let id: RevisionID
    let parentID: RevisionID?
    let createdAt: Date
    let source: String
    let renderedContent: String?
    let metadata: [String: String]
}

struct Artefact: Codable, Equatable, Identifiable, Sendable {
    let id: ArtefactID
    let createdAt: Date
    let kind: ArtefactKind
    private(set) var title: String
    private(set) var metadata: [String: String]
    private(set) var revisions: [ArtefactRevision]
    private(set) var currentRevisionID: RevisionID?

    init(
        id: ArtefactID = ArtefactID(),
        title: String,
        kind: ArtefactKind,
        createdAt: Date = Date(),
        metadata: [String: String] = [:],
        revisions: [ArtefactRevision] = [],
        currentRevisionID: RevisionID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.kind = kind
        self.metadata = metadata
        self.revisions = revisions
        self.currentRevisionID = currentRevisionID
    }

    var currentRevision: ArtefactRevision? {
        guard let currentRevisionID else { return nil }
        return revision(id: currentRevisionID)
    }

    func revision(id: RevisionID) -> ArtefactRevision? {
        revisions.first { $0.id == id }
    }

    mutating func setTitle(_ title: String) {
        self.title = title
    }

    @discardableResult
    mutating func checkpoint(
        source: String,
        renderedContent: String? = nil,
        metadata: [String: String] = [:],
        id: RevisionID = RevisionID(),
        createdAt: Date = Date()
    ) -> RevisionID {
        let revision = ArtefactRevision(
            id: id,
            parentID: currentRevisionID,
            createdAt: createdAt,
            source: source,
            renderedContent: renderedContent,
            metadata: metadata
        )
        revisions.append(revision)
        currentRevisionID = id
        return id
    }

    @discardableResult
    mutating func restore(
        revisionID: RevisionID,
        createdAt: Date = Date()
    ) throws -> RevisionID {
        guard let revision = revision(id: revisionID) else {
            throw ArtefactError.revisionNotFound(revisionID)
        }

        return checkpoint(
            source: revision.source,
            renderedContent: revision.renderedContent,
            metadata: revision.metadata,
            createdAt: createdAt
        )
    }
}
