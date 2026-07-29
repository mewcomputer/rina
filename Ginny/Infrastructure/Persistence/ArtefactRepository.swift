import Foundation
import SwiftData

enum ArtefactRepositoryError: Error, Equatable {
    case invalidArtefactID
    case invalidArtefactKind(String)
    case invalidRevisionID
    case invalidSkillRevisionID
    case malformedPayload
}

@Model
final class ArtefactRecord {
    @Attribute(.unique) var idValue: String
    var createdAt: Date
    var kindRaw: String
    var title: String
    var metadataData: Data
    var currentRevisionValue: String?

    @Relationship(deleteRule: .cascade, inverse: \ArtefactRevisionRecord.artefact)
    var revisionRecords: [ArtefactRevisionRecord]

    init(
        idValue: String,
        createdAt: Date,
        kindRaw: String,
        title: String,
        metadataData: Data,
        currentRevisionValue: String?,
        revisionRecords: [ArtefactRevisionRecord] = []
    ) {
        self.idValue = idValue
        self.createdAt = createdAt
        self.kindRaw = kindRaw
        self.title = title
        self.metadataData = metadataData
        self.currentRevisionValue = currentRevisionValue
        self.revisionRecords = revisionRecords
    }
}

@Model
final class ArtefactRevisionRecord {
    @Attribute(.unique) var idValue: String
    var parentIDValue: String?
    var createdAt: Date
    var source: String
    var renderedContent: String?
    var metadataData: Data
    var sortIndex: Int

    var artefact: ArtefactRecord?

    init(
        idValue: String,
        parentIDValue: String?,
        createdAt: Date,
        source: String,
        renderedContent: String?,
        metadataData: Data,
        sortIndex: Int
    ) {
        self.idValue = idValue
        self.parentIDValue = parentIDValue
        self.createdAt = createdAt
        self.source = source
        self.renderedContent = renderedContent
        self.metadataData = metadataData
        self.sortIndex = sortIndex
    }
}

@Model
final class SkillRecord {
    @Attribute(.unique) var idValue: String
    var createdAt: Date
    var name: String
    var summary: String
    var targetKindsData: Data
    var keywordsData: Data
    var isDiscoverable: Bool
    var isBuiltIn: Bool
    var currentRevisionValue: String

    @Relationship(deleteRule: .cascade, inverse: \SkillRevisionRecord.skill)
    var revisionRecords: [SkillRevisionRecord]

    init(
        idValue: String,
        createdAt: Date,
        name: String,
        summary: String,
        targetKindsData: Data,
        keywordsData: Data,
        isDiscoverable: Bool,
        isBuiltIn: Bool,
        currentRevisionValue: String,
        revisionRecords: [SkillRevisionRecord] = []
    ) {
        self.idValue = idValue
        self.createdAt = createdAt
        self.name = name
        self.summary = summary
        self.targetKindsData = targetKindsData
        self.keywordsData = keywordsData
        self.isDiscoverable = isDiscoverable
        self.isBuiltIn = isBuiltIn
        self.currentRevisionValue = currentRevisionValue
        self.revisionRecords = revisionRecords
    }
}

@Model
final class SkillRevisionRecord {
    @Attribute(.unique) var idValue: String
    var parentIDValue: String?
    var createdAt: Date
    var instructions: String
    var sortIndex: Int

    var skill: SkillRecord?

    init(
        idValue: String,
        parentIDValue: String?,
        createdAt: Date,
        instructions: String,
        sortIndex: Int
    ) {
        self.idValue = idValue
        self.parentIDValue = parentIDValue
        self.createdAt = createdAt
        self.instructions = instructions
        self.sortIndex = sortIndex
    }
}

@MainActor
final class ArtefactRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema([
            ArtefactRecord.self,
            ArtefactRevisionRecord.self,
            SkillRecord.self,
            SkillRevisionRecord.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        context = ModelContext(container)
    }

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
    }

    func fetchArtefacts() throws -> [Artefact] {
        let descriptor = FetchDescriptor<ArtefactRecord>(
            sortBy: [SortDescriptor(\ArtefactRecord.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(domainArtefact(from:))
    }

    func upsert(_ artefact: Artefact) throws {
        let idValue = artefact.id.rawValue.rawValue
        let descriptor = FetchDescriptor<ArtefactRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        let record: ArtefactRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = ArtefactRecord(
                idValue: idValue,
                createdAt: artefact.createdAt,
                kindRaw: artefact.kind.rawValue,
                title: artefact.title,
                metadataData: try encoder.encode(artefact.metadata),
                currentRevisionValue: artefact.currentRevisionID?.rawValue.rawValue
            )
            context.insert(record)
        }

        record.createdAt = artefact.createdAt
        record.kindRaw = artefact.kind.rawValue
        record.title = artefact.title
        record.metadataData = try encoder.encode(artefact.metadata)
        record.currentRevisionValue = artefact.currentRevisionID?.rawValue.rawValue
        try syncArtefactRevisions(artefact.revisions, into: record)
        try context.save()
    }

    func delete(_ artefact: Artefact) throws {
        let idValue = artefact.id.rawValue.rawValue
        let descriptor = FetchDescriptor<ArtefactRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    func fetchSkills() throws -> [Skill] {
        let descriptor = FetchDescriptor<SkillRecord>(
            sortBy: [SortDescriptor(\SkillRecord.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(domainSkill(from:))
    }

    func upsert(_ skill: Skill) throws {
        let idValue = skill.id
        let descriptor = FetchDescriptor<SkillRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        let record: SkillRecord
        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            record = SkillRecord(
                idValue: idValue,
                createdAt: skill.createdAt,
                name: skill.name,
                summary: skill.summary,
                targetKindsData: try encoder.encode(skill.targetKinds),
                keywordsData: try encoder.encode(skill.keywords),
                isDiscoverable: skill.isDiscoverable,
                isBuiltIn: skill.isBuiltIn,
                currentRevisionValue: skill.currentRevisionID.rawValue.rawValue
            )
            context.insert(record)
        }

        record.createdAt = skill.createdAt
        record.name = skill.name
        record.summary = skill.summary
        record.targetKindsData = try encoder.encode(skill.targetKinds)
        record.keywordsData = try encoder.encode(skill.keywords)
        record.isDiscoverable = skill.isDiscoverable
        record.isBuiltIn = skill.isBuiltIn
        record.currentRevisionValue = skill.currentRevisionID.rawValue.rawValue
        try syncSkillRevisions(skill.revisions, into: record)
        try context.save()
    }

    func delete(_ skill: Skill) throws {
        let idValue = skill.id
        let descriptor = FetchDescriptor<SkillRecord>(
            predicate: #Predicate { $0.idValue == idValue }
        )
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            try context.save()
        }
    }

    private func syncArtefactRevisions(
        _ revisions: [ArtefactRevision],
        into record: ArtefactRecord
    ) throws {
        let expectedIDs = Set(revisions.map { $0.id.rawValue.rawValue })
        for revisionRecord in record.revisionRecords
            where !expectedIDs.contains(revisionRecord.idValue)
        {
            context.delete(revisionRecord)
        }

        var revisionRecords: [ArtefactRevisionRecord] = []
        for (sortIndex, revision) in revisions.enumerated() {
            let idValue = revision.id.rawValue.rawValue
            let existing = record.revisionRecords.first { $0.idValue == idValue }
            let revisionRecord: ArtefactRevisionRecord
            if let existing {
                revisionRecord = existing
            } else {
                revisionRecord = ArtefactRevisionRecord(
                    idValue: idValue,
                    parentIDValue: revision.parentID?.rawValue.rawValue,
                    createdAt: revision.createdAt,
                    source: revision.source,
                    renderedContent: revision.renderedContent,
                    metadataData: try encoder.encode(revision.metadata),
                    sortIndex: sortIndex
                )
                context.insert(revisionRecord)
            }

            revisionRecord.parentIDValue = revision.parentID?.rawValue.rawValue
            revisionRecord.createdAt = revision.createdAt
            revisionRecord.source = revision.source
            revisionRecord.renderedContent = revision.renderedContent
            revisionRecord.metadataData = try encoder.encode(revision.metadata)
            revisionRecord.sortIndex = sortIndex
            revisionRecord.artefact = record
            revisionRecords.append(revisionRecord)
        }
        record.revisionRecords = revisionRecords
    }

    private func syncSkillRevisions(
        _ revisions: [SkillRevision],
        into record: SkillRecord
    ) throws {
        let expectedIDs = Set(revisions.map { $0.id.rawValue.rawValue })
        for revisionRecord in record.revisionRecords
            where !expectedIDs.contains(revisionRecord.idValue)
        {
            context.delete(revisionRecord)
        }

        var revisionRecords: [SkillRevisionRecord] = []
        for (sortIndex, revision) in revisions.enumerated() {
            let idValue = revision.id.rawValue.rawValue
            let existing = record.revisionRecords.first { $0.idValue == idValue }
            let revisionRecord: SkillRevisionRecord
            if let existing {
                revisionRecord = existing
            } else {
                revisionRecord = SkillRevisionRecord(
                    idValue: idValue,
                    parentIDValue: revision.parentID?.rawValue.rawValue,
                    createdAt: revision.createdAt,
                    instructions: revision.instructions,
                    sortIndex: sortIndex
                )
                context.insert(revisionRecord)
            }

            revisionRecord.parentIDValue = revision.parentID?.rawValue.rawValue
            revisionRecord.createdAt = revision.createdAt
            revisionRecord.instructions = revision.instructions
            revisionRecord.sortIndex = sortIndex
            revisionRecord.skill = record
            revisionRecords.append(revisionRecord)
        }
        record.revisionRecords = revisionRecords
    }

    private func domainArtefact(from record: ArtefactRecord) throws -> Artefact {
        guard let id = try? TID(string: record.idValue) else {
            throw ArtefactRepositoryError.invalidArtefactID
        }
        guard let kind = ArtefactKind(rawValue: record.kindRaw) else {
            throw ArtefactRepositoryError.invalidArtefactKind(record.kindRaw)
        }

        let revisions = try record.revisionRecords
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(domainArtefactRevision(from:))
        let currentRevisionID = try record.currentRevisionValue.map { value in
            guard let id = try? TID(string: value) else {
                throw ArtefactRepositoryError.invalidRevisionID
            }
            return RevisionID(rawValue: id)
        }

        return Artefact(
            id: ArtefactID(rawValue: id),
            title: record.title,
            kind: kind,
            createdAt: record.createdAt,
            metadata: try decoder.decode([String: String].self, from: record.metadataData),
            revisions: revisions,
            currentRevisionID: currentRevisionID
        )
    }

    private func domainArtefactRevision(from record: ArtefactRevisionRecord) throws -> ArtefactRevision {
        guard let id = try? TID(string: record.idValue) else {
            throw ArtefactRepositoryError.invalidRevisionID
        }
        let parentID = try record.parentIDValue.map { value in
            guard let id = try? TID(string: value) else {
                throw ArtefactRepositoryError.invalidRevisionID
            }
            return RevisionID(rawValue: id)
        }

        return ArtefactRevision(
            id: RevisionID(rawValue: id),
            parentID: parentID,
            createdAt: record.createdAt,
            source: record.source,
            renderedContent: record.renderedContent,
            metadata: try decoder.decode([String: String].self, from: record.metadataData)
        )
    }

    private func domainSkill(from record: SkillRecord) throws -> Skill {
        let revisions = try record.revisionRecords
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(domainSkillRevision(from:))
        guard let currentRevisionID = try? TID(string: record.currentRevisionValue) else {
            throw ArtefactRepositoryError.invalidSkillRevisionID
        }

        return Skill(
            id: record.idValue,
            name: record.name,
            summary: record.summary,
            instructions: revisions.first?.instructions ?? "",
            targetKinds: try decoder.decode(Set<ArtefactKind>.self, from: record.targetKindsData),
            keywords: try decoder.decode([String].self, from: record.keywordsData),
            isDiscoverable: record.isDiscoverable,
            isBuiltIn: record.isBuiltIn,
            createdAt: record.createdAt,
            revisions: revisions,
            currentRevisionID: RevisionID(rawValue: currentRevisionID)
        )
    }

    private func domainSkillRevision(from record: SkillRevisionRecord) throws -> SkillRevision {
        guard let id = try? TID(string: record.idValue) else {
            throw ArtefactRepositoryError.invalidSkillRevisionID
        }
        let parentID = try record.parentIDValue.map { value in
            guard let id = try? TID(string: value) else {
                throw ArtefactRepositoryError.invalidSkillRevisionID
            }
            return RevisionID(rawValue: id)
        }

        return SkillRevision(
            id: RevisionID(rawValue: id),
            parentID: parentID,
            createdAt: record.createdAt,
            instructions: record.instructions
        )
    }
}
