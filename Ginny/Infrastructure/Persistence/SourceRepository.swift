import Foundation
import SwiftData

enum SourceRepositoryError: Error, Equatable, Sendable {
    case invalidSourceID
    case immutableContentChanged
    case malformedPayload
}

@Model
final class SourceRecord {
    @Attribute(.unique) var idValue: String
    var createdAt: Date
    var displayName: String
    var contentTypeIdentifier: String
    var byteCount: Int
    var digest: String
    var storageKey: String
    var extractionStateData: Data
    var extractedText: String?
    var extractorVersion: String?
    var extractionProvenance: String?
    var metadataData: Data

    init(
        idValue: String,
        createdAt: Date,
        displayName: String,
        contentTypeIdentifier: String,
        byteCount: Int,
        digest: String,
        storageKey: String,
        extractionStateData: Data,
        extractedText: String?,
        extractorVersion: String?,
        extractionProvenance: String?,
        metadataData: Data
    ) {
        self.idValue = idValue
        self.createdAt = createdAt
        self.displayName = displayName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.digest = digest
        self.storageKey = storageKey
        self.extractionStateData = extractionStateData
        self.extractedText = extractedText
        self.extractorVersion = extractorVersion
        self.extractionProvenance = extractionProvenance
        self.metadataData = metadataData
    }
}

@MainActor
final class SourceRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema([SourceRecord.self])
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

    func fetch() throws -> [Source] {
        let descriptor = FetchDescriptor<SourceRecord>(
            sortBy: [SortDescriptor(\SourceRecord.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(domainSource(from:))
    }

    func upsert(_ source: Source) throws {
        let idValue = source.id.rawValue.uuidString
        let descriptor = FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        let record: SourceRecord
        if let existing = try context.fetch(descriptor).first {
            guard existing.digest == source.digest,
                  existing.storageKey == source.storageKey,
                  existing.byteCount == source.byteCount,
                  existing.contentTypeIdentifier == source.contentTypeIdentifier
            else {
                throw SourceRepositoryError.immutableContentChanged
            }
            record = existing
        } else {
            record = SourceRecord(
                idValue: idValue,
                createdAt: source.createdAt,
                displayName: source.displayName,
                contentTypeIdentifier: source.contentTypeIdentifier,
                byteCount: source.byteCount,
                digest: source.digest,
                storageKey: source.storageKey,
                extractionStateData: try encoder.encode(source.extractionState),
                extractedText: source.extractedText,
                extractorVersion: source.extractorVersion,
                extractionProvenance: source.extractionProvenance,
                metadataData: try encoder.encode(source.metadata)
            )
            context.insert(record)
        }

        record.displayName = source.displayName
        record.extractionStateData = try encoder.encode(source.extractionState)
        record.extractedText = source.extractedText
        record.extractorVersion = source.extractorVersion
        record.extractionProvenance = source.extractionProvenance
        record.metadataData = try encoder.encode(source.metadata)
        try context.save()
    }

    func delete(_ source: Source) throws {
        let idValue = source.id.rawValue.uuidString
        let descriptor = FetchDescriptor<SourceRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    private func domainSource(from record: SourceRecord) throws -> Source {
        guard let uuid = UUID(uuidString: record.idValue) else {
            throw SourceRepositoryError.invalidSourceID
        }

        do {
            return Source(
                id: SourceID(rawValue: uuid),
                createdAt: record.createdAt,
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                byteCount: record.byteCount,
                digest: record.digest,
                storageKey: record.storageKey,
                extractionState: try decoder.decode(
                    SourceExtractionState.self,
                    from: record.extractionStateData
                ),
                extractedText: record.extractedText,
                extractorVersion: record.extractorVersion,
                extractionProvenance: record.extractionProvenance,
                metadata: try decoder.decode([String: String].self, from: record.metadataData)
            )
        } catch let error as SourceRepositoryError {
            throw error
        } catch {
            throw SourceRepositoryError.malformedPayload
        }
    }
}
