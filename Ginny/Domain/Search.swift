import Foundation

enum SearchDocumentKind: String, Codable, CaseIterable, Equatable, Sendable {
    case conversation
    case message
    case artefact
    case artefactRevision
    case source
    case context
    case relationship
}

struct SearchDocument: Codable, Equatable, Sendable {
    let id: GraphNodeID
    let kind: SearchDocumentKind
    let title: String?
    let content: String
    let metadata: [String: String]
    let createdAt: Date

    init(
        id: GraphNodeID,
        kind: SearchDocumentKind,
        title: String? = nil,
        content: String,
        metadata: [String: String] = [:],
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

struct SearchResult: Equatable, Sendable {
    let nodeID: GraphNodeID
    let kind: SearchDocumentKind
    let title: String?
    let snippet: String
    let score: Double
}

struct SearchIndexStatus: Equatable, Sendable {
    let sourceVersion: Int
    let indexedVersion: Int
    let pendingChangeCount: Int

    var isCurrent: Bool {
        sourceVersion == indexedVersion && pendingChangeCount == 0
    }
}

enum SearchIndexChange: Sendable {
    case upsert(SearchDocument)
    case remove(GraphNodeID)
    case upsertRelationship(RelationshipEdge)
    case removeRelationship(RelationshipID)
}

enum SearchDocumentFactory {
    static func documents(
        for conversation: Conversation,
        artefacts: [Artefact] = [],
        sources: [Source] = [],
        contexts: [Context] = [],
        relationships: [RelationshipEdge] = []
    ) -> [SearchDocument] {
        var documents = documents(for: conversation)
        documents.append(contentsOf: artefacts.flatMap(documents(for:)))
        documents.append(contentsOf: sources.map(document(for:)))
        documents.append(contentsOf: contexts.map(document(for:)))
        documents.append(contentsOf: relationships.map(document(for:)))
        return documents
    }

    static func documents(for conversation: Conversation) -> [SearchDocument] {
        var documents = [SearchDocument(
            id: .conversation(conversation.id),
            kind: .conversation,
            title: conversation.title,
            content: conversation.messages.flatMap(\.blocks).map(content).joined(separator: "\n"),
            metadata: ["generationState": conversation.generationState.rawValue],
            createdAt: conversation.createdAt
        )]

        documents.append(contentsOf: conversation.messages.map { message in
            SearchDocument(
                id: .message(message.id),
                kind: .message,
                title: message.role.rawValue.capitalized,
                content: message.blocks.map(content).joined(separator: "\n"),
                metadata: [
                    "role": message.role.rawValue,
                    "conversationID": conversation.id.rawValue.uuidString
                ],
                createdAt: message.createdAt
            )
        })
        return documents
    }

    static func documents(for artefact: Artefact) -> [SearchDocument] {
        var documents = [SearchDocument(
            id: .artefact(artefact.id),
            kind: .artefact,
            title: artefact.title,
            content: artefact.currentRevision?.source ?? "",
            metadata: ["kind": artefact.kind.rawValue],
            createdAt: artefact.createdAt
        )]

        documents.append(contentsOf: artefact.revisions.map { revision in
            SearchDocument(
                id: .artefactRevision(artefactID: artefact.id, revisionID: revision.id),
                kind: .artefactRevision,
                title: artefact.title,
                content: revision.source,
                metadata: [
                    "artefactID": artefact.id.rawValue.uuidString,
                    "revisionID": revision.id.rawValue.uuidString
                ],
                createdAt: revision.createdAt
            )
        })
        return documents
    }

    static func document(for source: Source) -> SearchDocument {
        SearchDocument(
            id: .source(source.id),
            kind: .source,
            title: source.displayName,
            content: source.extractedText ?? "",
            metadata: [
                "contentType": source.contentTypeIdentifier,
                "extractionState": extractionStateLabel(source.extractionState),
                "digest": source.digest
            ],
            createdAt: source.createdAt
        )
    }

    static func document(for context: Context) -> SearchDocument {
        SearchDocument(
            id: .context(context.id),
            kind: .context,
            title: context.name,
            content: context.members.map(memberLabel).joined(separator: "\n"),
            metadata: ["memberCount": String(context.members.count)],
            createdAt: context.createdAt
        )
    }

    static func document(for relationship: RelationshipEdge) -> SearchDocument {
        SearchDocument(
            id: .contentBlock(ContentBlockID(rawValue: relationship.id.rawValue)),
            kind: .relationship,
            title: relationship.predicate.rawValue,
            content: relationship.attributes
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n"),
            metadata: [
                "source": nodeLabel(relationship.source),
                "target": nodeLabel(relationship.target),
                "predicate": relationship.predicate.rawValue
            ],
            createdAt: relationship.createdAt
        )
    }

    private static func content(_ block: ContentBlock) -> String {
        let attributeText = block.attributes
            .filter { $0.key != ContentBlock.schemaVersionKey }
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " ")
        return [block.payload, attributeText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func memberLabel(_ member: ContextMember) -> String {
        switch member {
        case .message(let id): "message:\(id.rawValue.uuidString)"
        case .artefactRevision(let artefactID, let revisionID):
            "artefactRevision:\(artefactID.rawValue.uuidString):\(revisionID.rawValue.uuidString)"
        case .source(let id): "source:\(id.rawValue.uuidString)"
        }
    }

    private static func extractionStateLabel(_ state: SourceExtractionState) -> String {
        switch state {
        case .pending: "pending"
        case .extracting: "extracting"
        case .ready: "ready"
        case .partiallyReady: "partiallyReady"
        case .failed: "failed"
        }
    }

    private static func nodeLabel(_ nodeID: GraphNodeID) -> String {
        switch nodeID {
        case .conversation(let id): "conversation:\(id.rawValue.uuidString)"
        case .message(let id): "message:\(id.rawValue.uuidString)"
        case .contentBlock(let id): "contentBlock:\(id.rawValue.uuidString)"
        case .artefact(let id): "artefact:\(id.rawValue.uuidString)"
        case .artefactRevision(let artefactID, let revisionID):
            "artefactRevision:\(artefactID.rawValue.uuidString):\(revisionID.rawValue.uuidString)"
        case .source(let id): "source:\(id.rawValue.uuidString)"
        case .context(let id): "context:\(id.rawValue.uuidString)"
        case .skill(let name): "skill:\(name)"
        }
    }
}

actor LocalSearchIndex {
    private var documents: [GraphNodeID: SearchDocument] = [:]
    private var relationships: [RelationshipID: RelationshipEdge] = [:]
    private var pendingChanges: [SearchIndexChange] = []
    private var sourceVersion = 0
    private var indexedVersion = 0

    func enqueue(_ change: SearchIndexChange) {
        pendingChanges.append(change)
        sourceVersion += 1
    }

    func enqueue(contentsOf changes: [SearchIndexChange]) {
        pendingChanges.append(contentsOf: changes)
        sourceVersion += changes.count
    }

    func flush() {
        for change in pendingChanges {
            switch change {
            case .upsert(let document):
                documents[document.id] = document
            case .remove(let nodeID):
                documents.removeValue(forKey: nodeID)
            case .upsertRelationship(let edge):
                relationships[edge.id] = edge
            case .removeRelationship(let relationshipID):
                relationships.removeValue(forKey: relationshipID)
            }
        }
        pendingChanges.removeAll(keepingCapacity: true)
        indexedVersion = sourceVersion
    }

    func status() -> SearchIndexStatus {
        SearchIndexStatus(
            sourceVersion: sourceVersion,
            indexedVersion: indexedVersion,
            pendingChangeCount: pendingChanges.count
        )
    }

    func search(
        query: String,
        limit: Int = 50,
        now: Date = Date()
    ) -> [SearchResult] {
        guard limit > 0 else { return [] }
        let queryTerms = Self.tokens(in: query)
        guard !queryTerms.isEmpty else { return [] }

        let lexicalScores = documents.values.reduce(into: [GraphNodeID: Double]()) { scores, document in
            let score = Self.lexicalScore(for: document, query: query, terms: queryTerms)
            if score > 0 {
                scores[document.id] = score
            }
        }

        return documents.values.compactMap { document in
            let lexicalScore = lexicalScores[document.id] ?? 0
            let proximityScore = relationshipProximityScore(
                for: document.id,
                lexicalScores: lexicalScores
            )
            guard lexicalScore > 0 || proximityScore > 0 else { return nil }

            let score = lexicalScore
                + proximityScore
                + recencyScore(for: document.createdAt, now: now)
            return SearchResult(
                nodeID: document.id,
                kind: document.kind,
                title: document.title,
                snippet: Self.snippet(for: document, queryTerms: queryTerms),
                score: score
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return Self.nodeSortKey($0.nodeID) < Self.nodeSortKey($1.nodeID)
        }
        .prefix(limit)
        .map { $0 }
    }

    private func relationshipProximityScore(
        for nodeID: GraphNodeID,
        lexicalScores: [GraphNodeID: Double]
    ) -> Double {
        relationships.values.reduce(0) { score, edge in
            let neighbor: GraphNodeID?
            if edge.source == nodeID {
                neighbor = edge.target
            } else if edge.target == nodeID {
                neighbor = edge.source
            } else {
                neighbor = nil
            }

            guard let neighbor, lexicalScores[neighbor] != nil else { return score }
            return score + (edge.predicate == .supportedBy ? 3 : 2)
        }
    }

    private func recencyScore(for date: Date, now: Date) -> Double {
        let ageInDays = max(0, now.timeIntervalSince(date) / 86_400)
        return 1 / (1 + ageInDays / 30)
    }

    private static func lexicalScore(
        for document: SearchDocument,
        query: String,
        terms: [String]
    ) -> Double {
        let title = document.title ?? ""
        let content = document.content
        let metadata = document.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " ")
        let normalizedQuery = normalized(query)
        var score = 0.0

        for term in terms {
            score += Double(count(of: term, in: normalized(title))) * 12
            score += Double(count(of: term, in: normalized(content))) * 4
            score += Double(count(of: term, in: normalized(metadata))) * 2
        }

        if !normalizedQuery.isEmpty && normalized(title).contains(normalizedQuery) {
            score += 8
        }
        return score
    }

    private static func snippet(for document: SearchDocument, queryTerms: [String]) -> String {
        let source = document.content.isEmpty ? (document.title ?? "") : document.content
        guard source.count > 180,
              let term = queryTerms.first(where: { normalized(source).contains($0) }),
              let range = normalized(source).range(of: term)
        else {
            return String(source.prefix(180))
        }

        let offset = normalized(source).distance(from: normalized(source).startIndex, to: range.lowerBound)
        let start = max(0, offset - 60)
        let end = min(source.count, start + 180)
        let startIndex = source.index(source.startIndex, offsetBy: start)
        let endIndex = source.index(source.startIndex, offsetBy: end)
        return String(source[startIndex..<endIndex])
    }

    private static func count(of term: String, in text: String) -> Int {
        text.split(separator: " ").reduce(into: 0) { count, word in
            if word == Substring(term) { count += 1 }
        }
    }

    private static func tokens(in text: String) -> [String] {
        normalized(text)
            .split(separator: " ")
            .map(String.init)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().map { character in
            character.isLetter || character.isNumber ? character : " "
        }.reduce(into: "") { result, character in
            if character == " " && result.last == " " { return }
            result.append(character)
        }
    }

    private static func nodeSortKey(_ nodeID: GraphNodeID) -> String {
        switch nodeID {
        case .conversation(let id): "conversation:\(id.rawValue.uuidString)"
        case .message(let id): "message:\(id.rawValue.uuidString)"
        case .contentBlock(let id): "contentBlock:\(id.rawValue.uuidString)"
        case .artefact(let id): "artefact:\(id.rawValue.uuidString)"
        case .artefactRevision(let artefactID, let revisionID):
            "artefactRevision:\(artefactID.rawValue.uuidString):\(revisionID.rawValue.uuidString)"
        case .source(let id): "source:\(id.rawValue.uuidString)"
        case .context(let id): "context:\(id.rawValue.uuidString)"
        case .skill(let name): "skill:\(name)"
        }
    }
}

enum WebSearchProviderID: String, CaseIterable, Codable, Equatable, Sendable {
    case tavily
    case exa

    var displayName: String {
        switch self {
        case .tavily: "Tavily"
        case .exa: "Exa"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .tavily: "https://api.tavily.com"
        case .exa: "https://api.exa.ai"
        }
    }

    var credentialID: String {
        "\(rawValue)-search-api-key"
    }
}

enum WebSearchRecency: String, CaseIterable, Codable, Equatable, Sendable {
    case day
    case week
    case month
    case year
}

struct WebSearchRequest: Codable, Equatable, Sendable {
    let query: String
    let maxResults: Int
    let includeDomains: [String]
    let excludeDomains: [String]
    let recency: WebSearchRecency?
    let includeAnswer: Bool

    init(
        query: String,
        maxResults: Int = 5,
        includeDomains: [String] = [],
        excludeDomains: [String] = [],
        recency: WebSearchRecency? = nil,
        includeAnswer: Bool = false
    ) {
        self.query = query
        self.maxResults = min(max(maxResults, 1), 100)
        self.includeDomains = includeDomains
        self.excludeDomains = excludeDomains
        self.recency = recency
        self.includeAnswer = includeAnswer
    }
}

struct WebSearchResult: Codable, Equatable, Sendable {
    let citationID: String
    let title: String
    let url: String
    let snippet: String
    let publishedAt: String?
    let author: String?
    let score: Double?
    let provider: WebSearchProviderID

    init(
        citationID: String? = nil,
        title: String,
        url: String,
        snippet: String,
        publishedAt: String? = nil,
        author: String? = nil,
        score: Double? = nil,
        provider: WebSearchProviderID
    ) {
        self.citationID = citationID ?? "\(provider.rawValue):\(url)"
        self.title = title
        self.url = url
        self.snippet = snippet
        self.publishedAt = publishedAt
        self.author = author
        self.score = score
        self.provider = provider
    }

    private enum CodingKeys: String, CodingKey {
        case citationID = "citation_id"
        case title
        case url
        case snippet
        case publishedAt = "published_at"
        case author
        case score
        case provider
    }
}

struct WebSearchResponse: Codable, Equatable, Sendable {
    let query: String
    let provider: WebSearchProviderID
    let answer: String?
    let results: [WebSearchResult]
}

struct WebSearchConfiguration: Equatable, Sendable {
    let provider: WebSearchProviderID
    let baseURL: URL
}

enum WebSearchPreferences {
    static let providerKey = "webSearch.provider"
    static let baseURLKeyPrefix = "webSearch.baseURL."
}
