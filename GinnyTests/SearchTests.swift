import Foundation
import XCTest
@testable import Ginny

final class SearchTests: XCTestCase {
    func testIndexIsEventuallyConsistentAndCoalescesDocumentUpdates() async {
        let index = LocalSearchIndex()
        let node = GraphNodeID.source(SourceID())

        await index.enqueue(.upsert(SearchDocument(
            id: node,
            kind: .source,
            title: "Old notes",
            content: "An unrelated draft",
            createdAt: Date(timeIntervalSince1970: 10)
        )))
        await index.enqueue(.upsert(SearchDocument(
            id: node,
            kind: .source,
            title: "Release notes",
            content: "The streaming renderer is ready",
            createdAt: Date(timeIntervalSince1970: 10)
        )))

        let pendingResults = await index.search(query: "streaming")
        let pendingStatus = await index.status()
        XCTAssertEqual(pendingResults, [])
        XCTAssertEqual(pendingStatus.pendingChangeCount, 2)

        await index.flush()

        let results = await index.search(query: "streaming")
        XCTAssertEqual(results.map(\.nodeID), [node])
        XCTAssertEqual(results.first?.title, "Release notes")
        let currentStatus = await index.status()
        XCTAssertEqual(currentStatus.pendingChangeCount, 0)
        XCTAssertEqual(currentStatus.indexedVersion, 2)
    }

    func testSearchRanksTitleAndRecentContentDeterministically() async {
        let index = LocalSearchIndex()
        let oldTitle = GraphNodeID.artefact(ArtefactID())
        let recentContent = GraphNodeID.source(SourceID())
        let now = Date(timeIntervalSince1970: 1_000_000)

        await index.enqueue(contentsOf: [
            .upsert(SearchDocument(
                id: oldTitle,
                kind: .artefact,
                title: "Streaming architecture",
                content: "A short note",
                createdAt: now.addingTimeInterval(-60 * 60 * 24 * 90)
            )),
            .upsert(SearchDocument(
                id: recentContent,
                kind: .source,
                title: "Notes",
                content: "Streaming renderer implementation details",
                createdAt: now.addingTimeInterval(-60 * 60 * 24)
            ))
        ])
        await index.flush()

        let results = await index.search(query: "streaming", now: now)

        XCTAssertEqual(results.map(\.nodeID), [oldTitle, recentContent])
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testRelationshipProximityBoostsARelevantDocument() async {
        let index = LocalSearchIndex()
        let source = GraphNodeID.source(SourceID())
        let artefact = GraphNodeID.artefact(ArtefactID())
        let edge = RelationshipEdge(
            source: source,
            predicate: .supportedBy,
            target: artefact
        )

        await index.enqueue(contentsOf: [
            .upsert(SearchDocument(
                id: source,
                kind: .source,
                title: "Research",
                content: "The source contains the key fact",
                createdAt: Date(timeIntervalSince1970: 10)
            )),
            .upsert(SearchDocument(
                id: artefact,
                kind: .artefact,
                title: "Draft",
                content: "A derived document",
                createdAt: Date(timeIntervalSince1970: 10)
            )),
            .upsertRelationship(edge)
        ])
        await index.flush()

        let results = await index.search(query: "key fact")

        XCTAssertEqual(results.map(\.nodeID), [source, artefact])
        XCTAssertGreaterThan(results[1].score, 0)
    }

    func testDocumentFactoryCoversSearchableDomainObjects() {
        var artefact = Artefact(title: "Plan", kind: .document)
        let revisionID = artefact.checkpoint(source: "A detailed implementation plan")
        let source = Source(
            displayName: "notes.md",
            contentTypeIdentifier: "public.markdown",
            byteCount: 10,
            digest: "digest",
            storageKey: "digest",
            extractionState: .ready,
            extractedText: "Important research"
        )
        let conversation = Conversation(
            title: "Project notes",
            messages: [
                Message.user("Build the search index", createdAt: Date(timeIntervalSince1970: 1))
            ]
        )
        let context = Context(
            name: "Release context",
            members: [.source(source.id)]
        )
        let edge = RelationshipEdge(
            source: .source(source.id),
            predicate: .supportedBy,
            target: .artefactRevision(artefactID: artefact.id, revisionID: revisionID)
        )

        let documents = SearchDocumentFactory.documents(
            for: conversation,
            artefacts: [artefact],
            sources: [source],
            contexts: [context],
            relationships: [edge]
        )

        XCTAssertEqual(
            Set(documents.map(\.kind)),
            Set(SearchDocumentKind.allCases)
        )
        XCTAssertTrue(documents.contains { $0.id == .message(conversation.messages[0].id) })
        XCTAssertTrue(documents.contains { $0.content.contains("Important research") })
        XCTAssertTrue(documents.contains { $0.title == "supportedBy" })
    }
}
