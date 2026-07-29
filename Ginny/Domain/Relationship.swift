import Foundation

enum GraphNodeID: Codable, Equatable, Hashable, Sendable {
    case conversation(ConversationID)
    case message(MessageID)
    case contentBlock(ContentBlockID)
    case artefact(ArtefactID)
    case artefactRevision(artefactID: ArtefactID, revisionID: RevisionID)
    case source(SourceID)
    case citation(CitationID)
    case context(ContextID)
    case relationship(RelationshipID)
    case skill(String)
}

enum RelationshipPredicate: String, Codable, CaseIterable, Equatable, Sendable {
    case relatedTo
    case derivedFrom
    case revisionOf
    case references
    case supportedBy
}

struct RelationshipEdge: Codable, Equatable, Identifiable, Sendable {
    let id: RelationshipID
    let createdAt: Date
    let source: GraphNodeID
    let predicate: RelationshipPredicate
    let target: GraphNodeID
    private(set) var attributes: [String: String]

    init(
        id: RelationshipID = RelationshipID(),
        createdAt: Date = Date(),
        source: GraphNodeID,
        predicate: RelationshipPredicate,
        target: GraphNodeID,
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.predicate = predicate
        self.target = target
        self.attributes = attributes
    }
}
