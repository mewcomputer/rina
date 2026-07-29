import Foundation
import SwiftData

enum RelationshipRepositoryError: Error, Equatable, Sendable {
    case invalidRelationshipID
    case malformedPayload
}

@Model
final class RelationshipRecord {
    @Attribute(.unique) var idValue: String
    var createdAt: Date
    var sourceData: Data
    var predicateRaw: String
    var targetData: Data
    var attributesData: Data

    init(
        idValue: String,
        createdAt: Date,
        sourceData: Data,
        predicateRaw: String,
        targetData: Data,
        attributesData: Data
    ) {
        self.idValue = idValue
        self.createdAt = createdAt
        self.sourceData = sourceData
        self.predicateRaw = predicateRaw
        self.targetData = targetData
        self.attributesData = attributesData
    }
}

@MainActor
final class RelationshipRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema([RelationshipRecord.self])
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

    func fetchOutgoing(
        from source: GraphNodeID,
        predicate: RelationshipPredicate? = nil
    ) throws -> [RelationshipEdge] {
        try fetch { edge in
            edge.source == source && (predicate == nil || edge.predicate == predicate)
        }
    }

    func fetchIncoming(
        to target: GraphNodeID,
        predicate: RelationshipPredicate? = nil
    ) throws -> [RelationshipEdge] {
        try fetch { edge in
            edge.target == target && (predicate == nil || edge.predicate == predicate)
        }
    }

    func fetch(predicate: RelationshipPredicate) throws -> [RelationshipEdge] {
        try fetch { $0.predicate == predicate }
    }

    func upsert(_ edge: RelationshipEdge) throws {
        let idValue = edge.id.rawValue.rawValue
        let descriptor = FetchDescriptor<RelationshipRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        let record: RelationshipRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = RelationshipRecord(
                idValue: idValue,
                createdAt: edge.createdAt,
                sourceData: try encoder.encode(edge.source),
                predicateRaw: edge.predicate.rawValue,
                targetData: try encoder.encode(edge.target),
                attributesData: try encoder.encode(edge.attributes)
            )
            context.insert(record)
        }

        record.createdAt = edge.createdAt
        record.sourceData = try encoder.encode(edge.source)
        record.predicateRaw = edge.predicate.rawValue
        record.targetData = try encoder.encode(edge.target)
        record.attributesData = try encoder.encode(edge.attributes)
        try context.save()
    }

    func delete(_ edge: RelationshipEdge) throws {
        let idValue = edge.id.rawValue.rawValue
        let descriptor = FetchDescriptor<RelationshipRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    private func fetch(
        matching predicate: (RelationshipEdge) -> Bool
    ) throws -> [RelationshipEdge] {
        let descriptor = FetchDescriptor<RelationshipRecord>(
            sortBy: [
                SortDescriptor(\RelationshipRecord.createdAt),
                SortDescriptor(\RelationshipRecord.idValue)
            ]
        )
        return try context.fetch(descriptor)
            .map(domainEdge(from:))
            .filter(predicate)
    }

    private func domainEdge(from record: RelationshipRecord) throws -> RelationshipEdge {
        guard let id = try? TID(string: record.idValue) else {
            throw RelationshipRepositoryError.invalidRelationshipID
        }
        guard let predicate = RelationshipPredicate(rawValue: record.predicateRaw) else {
            throw RelationshipRepositoryError.malformedPayload
        }

        do {
            return RelationshipEdge(
                id: RelationshipID(rawValue: id),
                createdAt: record.createdAt,
                source: try decoder.decode(GraphNodeID.self, from: record.sourceData),
                predicate: predicate,
                target: try decoder.decode(GraphNodeID.self, from: record.targetData),
                attributes: try decoder.decode([String: String].self, from: record.attributesData)
            )
        } catch let error as RelationshipRepositoryError {
            throw error
        } catch {
            throw RelationshipRepositoryError.malformedPayload
        }
    }
}
