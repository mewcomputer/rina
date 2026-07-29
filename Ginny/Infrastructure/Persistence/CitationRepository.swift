import Foundation
import SwiftData

enum CitationRepositoryError: Error, Equatable, Sendable {
    case invalidCitationID
    case malformedPayload
}

@Model
final class CitationRecord {
    @Attribute(.unique) var idValue: String
    var createdAt: Date
    var query: String
    var providerRaw: String
    var title: String
    var url: String
    var snippet: String
    var publishedAt: String?
    var author: String?
    var score: Double?

    init(
        idValue: String,
        createdAt: Date,
        query: String,
        providerRaw: String,
        title: String,
        url: String,
        snippet: String,
        publishedAt: String?,
        author: String?,
        score: Double?
    ) {
        self.idValue = idValue
        self.createdAt = createdAt
        self.query = query
        self.providerRaw = providerRaw
        self.title = title
        self.url = url
        self.snippet = snippet
        self.publishedAt = publishedAt
        self.author = author
        self.score = score
    }
}

@MainActor
final class CitationRepository {
    let container: ModelContainer
    private let context: ModelContext

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema([CitationRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
    }

    func fetch() throws -> [Citation] {
        let descriptor = FetchDescriptor<CitationRecord>(
            sortBy: [SortDescriptor(\CitationRecord.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(domainCitation(from:))
    }

    func upsert(_ citation: Citation) throws {
        let idValue = citation.id.rawValue.rawValue
        let descriptor = FetchDescriptor<CitationRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        let record: CitationRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = CitationRecord(
                idValue: idValue,
                createdAt: citation.createdAt,
                query: citation.query,
                providerRaw: citation.provider.rawValue,
                title: citation.title,
                url: citation.url,
                snippet: citation.snippet,
                publishedAt: citation.publishedAt,
                author: citation.author,
                score: citation.score
            )
            context.insert(record)
        }

        record.createdAt = citation.createdAt
        record.query = citation.query
        record.providerRaw = citation.provider.rawValue
        record.title = citation.title
        record.url = citation.url
        record.snippet = citation.snippet
        record.publishedAt = citation.publishedAt
        record.author = citation.author
        record.score = citation.score
        try context.save()
    }

    func delete(_ citation: Citation) throws {
        let idValue = citation.id.rawValue.rawValue
        let descriptor = FetchDescriptor<CitationRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    private func domainCitation(from record: CitationRecord) throws -> Citation {
        guard let id = try? TID(string: record.idValue),
              let provider = WebSearchProviderID(rawValue: record.providerRaw)
        else {
            throw CitationRepositoryError.invalidCitationID
        }

        return Citation(
            id: CitationID(rawValue: id),
            createdAt: record.createdAt,
            query: record.query,
            result: WebSearchResult(
                title: record.title,
                url: record.url,
                snippet: record.snippet,
                publishedAt: record.publishedAt,
                author: record.author,
                score: record.score,
                provider: provider
            )
        )
    }
}
