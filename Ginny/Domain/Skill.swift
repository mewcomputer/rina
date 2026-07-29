import Foundation

struct SkillRevision: Codable, Equatable, Identifiable, Sendable {
    let id: RevisionID
    let parentID: RevisionID?
    let createdAt: Date
    let instructions: String
}

struct Skill: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let isBuiltIn: Bool
    private(set) var name: String
    private(set) var summary: String
    private(set) var targetKinds: Set<ArtefactKind>
    private(set) var keywords: [String]
    private(set) var isDiscoverable: Bool
    private(set) var revisions: [SkillRevision]
    private(set) var currentRevisionID: RevisionID

    init(
        id: String = UUID().uuidString,
        name: String,
        summary: String,
        instructions: String,
        targetKinds: Set<ArtefactKind>,
        keywords: [String] = [],
        isDiscoverable: Bool = true,
        isBuiltIn: Bool = false,
        createdAt: Date = Date(),
        revisionID: RevisionID = RevisionID(),
        revisions: [SkillRevision]? = nil,
        currentRevisionID: RevisionID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.isBuiltIn = isBuiltIn
        self.name = name
        self.summary = summary
        self.targetKinds = targetKinds
        self.keywords = keywords
        self.isDiscoverable = isDiscoverable
        self.revisions = revisions ?? [
            SkillRevision(
                id: revisionID,
                parentID: nil,
                createdAt: createdAt,
                instructions: instructions
            )
        ]
        self.currentRevisionID = currentRevisionID ?? self.revisions.last?.id ?? revisionID
    }

    var currentRevision: SkillRevision? {
        revision(id: currentRevisionID)
    }

    func revision(id: RevisionID) -> SkillRevision? {
        revisions.first { $0.id == id }
    }

    mutating func updateMetadata(
        name: String,
        summary: String,
        targetKinds: Set<ArtefactKind>,
        keywords: [String],
        isDiscoverable: Bool
    ) {
        self.name = name
        self.summary = summary
        self.targetKinds = targetKinds
        self.keywords = keywords
        self.isDiscoverable = isDiscoverable
    }

    @discardableResult
    mutating func update(
        instructions: String,
        createdAt: Date = Date(),
        revisionID: RevisionID = RevisionID()
    ) -> RevisionID {
        let revision = SkillRevision(
            id: revisionID,
            parentID: currentRevisionID,
            createdAt: createdAt,
            instructions: instructions
        )
        revisions.append(revision)
        currentRevisionID = revisionID
        return revisionID
    }
}

struct SkillDescriptor: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let targetKinds: Set<ArtefactKind>
    let keywords: [String]
}

struct SkillCatalog: Sendable {
    let skills: [Skill]

    init(skills: [Skill] = CuratedSkills.all) {
        self.skills = skills
    }

    func skill(id: String) -> Skill? {
        skills.first { $0.id == id }
    }

    func discover(query: String, for kind: ArtefactKind? = nil) -> [SkillDescriptor] {
        let queryTerms = Self.terms(in: query)
        var matches: [(score: Int, descriptor: SkillDescriptor)] = []

        for skill in skills {
            guard skill.isDiscoverable else { continue }
            if let kind, !skill.targetKinds.contains(kind) { continue }

            let score = Self.score(skill: skill, queryTerms: queryTerms)
            guard queryTerms.isEmpty || score > 0 else { continue }
            matches.append((
                score: score,
                descriptor: SkillDescriptor(
                    id: skill.id,
                    name: skill.name,
                    summary: skill.summary,
                    targetKinds: skill.targetKinds,
                    keywords: skill.keywords
                )
            ))
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.descriptor.name.localizedCaseInsensitiveCompare(
                    rhs.descriptor.name
                ) == .orderedAscending
            }
            .map(\.descriptor)
    }

    private static func score(skill: Skill, queryTerms: Set<String>) -> Int {
        guard !queryTerms.isEmpty else { return 1 }

        let nameTerms = terms(in: skill.name)
        let summaryTerms = terms(in: skill.summary)
        let keywordTerms = Set(skill.keywords.flatMap(terms(in:)))

        return queryTerms.reduce(into: 0) { score, term in
            if keywordTerms.contains(term) { score += 3 }
            if nameTerms.contains(term) { score += 2 }
            if summaryTerms.contains(term) { score += 1 }
        }
    }

    private static func terms(in value: String) -> Set<String> {
        Set(
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}

enum CuratedSkills {
    static let frontendDesign = Skill(
        id: "ginny.frontend-design",
        name: "Frontend design",
        summary: "Create clear, accessible web artefacts with a coherent visual system.",
        instructions: """
        Design the artefact before writing it. Use semantic color tokens, responsive layout,
        accessible contrast, clear hierarchy, and restrained interaction. Prefer shadcn-inspired
        tokens such as background, foreground, muted, accent, primary, destructive, border, input,
        and ring. Keep inline artefacts self-contained and appropriate to the available space.
        """,
        targetKinds: [.web, .inlineWeb],
        keywords: ["frontend", "web", "react", "tailwind", "shadcn", "ui", "accessibility"],
        isDiscoverable: true,
        isBuiltIn: true
    )

    static let all: [Skill] = [frontendDesign]
}
