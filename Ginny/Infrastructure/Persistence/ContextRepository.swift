import Foundation
import SwiftData

enum ContextRepositoryError: Error, Equatable, Sendable {
    case invalidContextID
    case malformedPayload
}

@Model
final class ContextRecord {
    @Attribute(.unique) var idValue: String
    var createdAt: Date
    var name: String
    var membersData: Data

    init(idValue: String, createdAt: Date, name: String, membersData: Data) {
        self.idValue = idValue
        self.createdAt = createdAt
        self.name = name
        self.membersData = membersData
    }
}

@MainActor
final class ContextRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema([ContextRecord.self])
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

    func fetch() throws -> [Context] {
        let descriptor = FetchDescriptor<ContextRecord>(
            sortBy: [SortDescriptor(\ContextRecord.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(domainContext(from:))
    }

    func upsert(_ value: Context) throws {
        let idValue = value.id.rawValue.rawValue
        let descriptor = FetchDescriptor<ContextRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        let record: ContextRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = ContextRecord(
                idValue: idValue,
                createdAt: value.createdAt,
                name: value.name,
                membersData: try encoder.encode(value.members)
            )
            context.insert(record)
        }

        record.createdAt = value.createdAt
        record.name = value.name
        record.membersData = try encoder.encode(value.members)
        try context.save()
    }

    func delete(_ value: Context) throws {
        let idValue = value.id.rawValue.rawValue
        let descriptor = FetchDescriptor<ContextRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    private func domainContext(from record: ContextRecord) throws -> Context {
        guard let id = try? TID(string: record.idValue) else {
            throw ContextRepositoryError.invalidContextID
        }

        do {
            return Context(
                id: ContextID(rawValue: id),
                createdAt: record.createdAt,
                name: record.name,
                members: try decoder.decode([ContextMember].self, from: record.membersData)
            )
        } catch {
            throw ContextRepositoryError.malformedPayload
        }
    }
}
