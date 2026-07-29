import Foundation
import XCTest
@testable import Ginny

final class SearchTests: XCTestCase {
    func testTavilyProviderMapsResponseAndRequest() async throws {
        let recorder = SearchRequestRecorder()
        let transport = StubWebSearchTransport(
            recorder: recorder,
            data: Data("""
            {
              "answer": "Swift is a programming language.",
              "results": [
                {
                  "title": "Swift",
                  "url": "https://swift.org",
                  "content": "Swift is powerful and approachable.",
                  "score": 0.91,
                  "published_date": "2026-07-28T12:00:00Z"
                }
              ]
            }
            """.utf8)
        )
        let provider = TavilyWebSearchProvider(transport: transport)
        let request = WebSearchRequest(
            query: "swift concurrency",
            maxResults: 7,
            includeDomains: ["swift.org"],
            recency: .week,
            includeAnswer: true
        )

        let response = try await provider.search(
            request: request,
            baseURL: URL(string: "https://api.tavily.com")!,
            credential: "tavily-key"
        )

        let sentRequest = try await recorder.request()
        XCTAssertEqual(sentRequest.url?.absoluteString, "https://api.tavily.com/search")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "Authorization"), "Bearer tavily-key")
        let body = try XCTUnwrap(sentRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["query"] as? String, "swift concurrency")
        XCTAssertEqual(json["max_results"] as? Int, 7)
        XCTAssertEqual(json["time_range"] as? String, "week")
        XCTAssertEqual(json["include_domains"] as? [String], ["swift.org"])
        XCTAssertEqual(response.provider, .tavily)
        XCTAssertEqual(response.answer, "Swift is a programming language.")
        XCTAssertEqual(response.results.first?.title, "Swift")
        XCTAssertEqual(response.results.first?.snippet, "Swift is powerful and approachable.")
        XCTAssertEqual(response.results.first?.url, "https://swift.org")
    }

    func testExaProviderMapsHighlightsAndUsesItsRequestVocabulary() async throws {
        let recorder = SearchRequestRecorder()
        let transport = StubWebSearchTransport(
            recorder: recorder,
            data: Data("""
            {
              "results": [
                {
                  "title": "Swift concurrency",
                  "url": "https://example.com/swift",
                  "author": "Apple",
                  "publishedDate": "2026-07-27T12:00:00Z",
                  "highlights": ["Actors protect mutable state.", "Async code stays readable."]
                }
              ]
            }
            """.utf8)
        )
        let provider = ExaWebSearchProvider(transport: transport)
        let request = WebSearchRequest(
            query: "swift concurrency",
            maxResults: 4,
            excludeDomains: ["example.org"]
        )

        let response = try await provider.search(
            request: request,
            baseURL: URL(string: "https://api.exa.ai")!,
            credential: "exa-key"
        )

        let sentRequest = try await recorder.request()
        XCTAssertEqual(sentRequest.url?.absoluteString, "https://api.exa.ai/search")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "x-api-key"), "exa-key")
        let body = try XCTUnwrap(sentRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["query"] as? String, "swift concurrency")
        XCTAssertEqual(json["numResults"] as? Int, 4)
        XCTAssertEqual(json["excludeDomains"] as? [String], ["example.org"])
        XCTAssertEqual(
            ((json["contents"] as? [String: Any])?["highlights"] as? Bool),
            true
        )
        XCTAssertEqual(response.provider, .exa)
        XCTAssertEqual(response.results.first?.snippet, "Actors protect mutable state.\nAsync code stays readable.")
        XCTAssertEqual(response.results.first?.author, "Apple")
    }

    func testSearchWebToolExposesCitationsWithoutProviderSpecificArguments() async throws {
        let response = WebSearchResponse(
            query: "swift",
            provider: .tavily,
            answer: "A language.",
            results: [WebSearchResult(
                title: "Swift",
                url: "https://swift.org",
                snippet: "A programming language.",
                provider: .tavily
            )]
        )
        let tool = SearchWebTool(service: StubWebSearchService(response: response))

        XCTAssertEqual(tool.approvalRequirement, .automatic)
        XCTAssertEqual(tool.definition.name, "search_web")
        XCTAssertEqual(tool.definition.inputSchema.required, ["query"])
        XCTAssertNil(tool.definition.inputSchema.properties?["provider"])

        let output = try await tool.execute(arguments: """
        {"query":"swift","max_results":3,"include_answer":true}
        """)
        let decoded = try JSONDecoder().decode(WebSearchResponse.self, from: Data(output.utf8))
        XCTAssertEqual(decoded, response)
    }

    func testSearchWorkspaceToolReturnsLocalResultsWithoutApproval() async throws {
        let citation = Citation.from(
            WebSearchResult(
                title: "Swift actors",
                url: "https://swift.org/actors",
                snippet: "Actors protect mutable state.",
                provider: .tavily
            ),
            query: "actors"
        )
        let index = LocalSearchIndex()
        await index.enqueue(.upsert(SearchDocumentFactory.document(for: citation)))
        await index.flush()
        let tool = SearchWorkspaceTool(index: index)

        XCTAssertEqual(tool.approvalRequirement, .automatic)
        let output = try await tool.execute(arguments: "{\"query\":\"actors\"}")
        let results = try JSONDecoder().decode([SearchResult].self, from: Data(output.utf8))

        XCTAssertEqual(results.first?.nodeID, .citation(citation.id))
        XCTAssertEqual(results.first?.kind, .citation)
    }

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
        let citation = Citation.from(
            WebSearchResult(
                title: "Swift",
                url: "https://swift.org",
                snippet: "A programming language.",
                provider: .tavily
            ),
            query: "swift"
        )

        let documents = SearchDocumentFactory.documents(
            for: conversation,
            artefacts: [artefact],
            sources: [source],
            contexts: [context],
            relationships: [edge],
            citations: [citation]
        )

        XCTAssertEqual(
            Set(documents.map(\.kind)),
            Set(SearchDocumentKind.allCases)
        )
        XCTAssertTrue(documents.contains { $0.id == .message(conversation.messages[0].id) })
        XCTAssertTrue(documents.contains { $0.content.contains("Important research") })
        XCTAssertTrue(documents.contains { $0.title == "supportedBy" })
        XCTAssertTrue(documents.contains { $0.id == .relationship(edge.id) })
        XCTAssertTrue(documents.contains { $0.id == .citation(citation.id) })
    }

    func testLocalSearchIndexesPersistedCitationsWithTheirMetadata() async {
        let citation = Citation.from(
            WebSearchResult(
                title: "Swift concurrency",
                url: "https://swift.org/concurrency",
                snippet: "Actors protect mutable state.",
                provider: .exa
            ),
            query: "actors"
        )
        let index = LocalSearchIndex()

        await index.enqueue(.upsert(SearchDocumentFactory.document(for: citation)))
        await index.flush()

        let results = await index.search(query: "actors")
        XCTAssertEqual(results.first?.nodeID, .citation(citation.id))
        XCTAssertEqual(results.first?.kind, .citation)
    }
}

private actor SearchRequestRecorder {
    private var recordedRequest: URLRequest?

    func record(_ request: URLRequest) {
        recordedRequest = request
    }

    func request() throws -> URLRequest {
        guard let recordedRequest else {
            throw NSError(domain: "SearchTests", code: 1)
        }
        return recordedRequest
    }
}

private struct StubWebSearchTransport: WebSearchTransport {
    let recorder: SearchRequestRecorder
    let data: Data

    func response(for request: URLRequest) async throws -> WebSearchHTTPResponse {
        await recorder.record(request)
        return WebSearchHTTPResponse(statusCode: 200, data: data)
    }
}

private struct StubWebSearchService: WebSearchProviding {
    let response: WebSearchResponse

    func search(_ request: WebSearchRequest) async throws -> WebSearchResponse {
        response
    }
}
