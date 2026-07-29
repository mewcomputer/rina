import Foundation
import XCTest
@testable import Ginny

@MainActor
final class RelationshipTests: XCTestCase {
    func testRelationshipRepositoryRoundTripsTypedEdges() throws {
        let repository = try RelationshipRepository(isStoredInMemoryOnly: true)
        let edge = RelationshipEdge(
            source: .source(SourceID()),
            predicate: .supportedBy,
            target: .artefactRevision(
                artefactID: ArtefactID(),
                revisionID: RevisionID()
            ),
            attributes: ["quote": "The source supports this revision."]
        )

        try repository.upsert(edge)

        XCTAssertEqual(try repository.fetchOutgoing(from: edge.source), [edge])
        XCTAssertEqual(try repository.fetchIncoming(to: edge.target), [edge])
        XCTAssertEqual(try repository.fetch(predicate: .supportedBy), [edge])
    }

    func testRelationshipQueriesAreScopedByPredicateAndStableByCreationTime() throws {
        let repository = try RelationshipRepository(isStoredInMemoryOnly: true)
        let source = GraphNodeID.source(SourceID())
        let target = GraphNodeID.artefact(ArtefactID())
        let earlier = RelationshipEdge(
            createdAt: Date(timeIntervalSince1970: 10),
            source: source,
            predicate: .derivedFrom,
            target: target
        )
        let later = RelationshipEdge(
            createdAt: Date(timeIntervalSince1970: 20),
            source: source,
            predicate: .references,
            target: target
        )

        try repository.upsert(later)
        try repository.upsert(earlier)

        XCTAssertEqual(try repository.fetchOutgoing(from: source), [earlier, later])
        XCTAssertEqual(try repository.fetchOutgoing(from: source, predicate: .references), [later])
        XCTAssertEqual(try repository.fetchIncoming(to: target, predicate: .derivedFrom), [earlier])
    }

    func testDeletingAnEdgeDoesNotDeleteOtherEdges() throws {
        let repository = try RelationshipRepository(isStoredInMemoryOnly: true)
        let source = GraphNodeID.message(MessageID())
        let first = RelationshipEdge(source: source, predicate: .relatedTo, target: .source(SourceID()))
        let second = RelationshipEdge(source: source, predicate: .references, target: .artefact(ArtefactID()))
        try repository.upsert(first)
        try repository.upsert(second)

        try repository.delete(first)

        XCTAssertEqual(try repository.fetchOutgoing(from: source), [second])
    }

    func testCitationRepositoryRoundTripsDeterministicCitations() throws {
        let repository = try CitationRepository(isStoredInMemoryOnly: true)
        let result = WebSearchResult(
            title: "Swift",
            url: "https://swift.org",
            snippet: "A programming language.",
            provider: .tavily
        )
        let first = Citation.from(result, query: "swift")
        let second = Citation.from(result, query: "swift again")

        XCTAssertEqual(first.id, second.id)
        try repository.upsert(first)
        try repository.upsert(second)

        let fetched = try repository.fetch()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.query, "swift again")
        XCTAssertEqual(fetched.first?.url, result.url)
    }
}
