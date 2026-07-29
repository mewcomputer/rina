import Combine
import Foundation

@MainActor
final class ArtefactStore: ObservableObject {
    @Published private(set) var artefacts: [Artefact]
    @Published private(set) var skills: [Skill]
    @Published private(set) var persistenceError: String?

    private let repository: ArtefactRepository

    init(repository: ArtefactRepository) {
        self.repository = repository
        self.artefacts = []
        self.skills = []
        self.persistenceError = nil
        refresh()
    }

    var availableSkills: [Skill] {
        let userSkillsByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        let curatedIDs = Set(CuratedSkills.all.map(\.id))
        return CuratedSkills.all.map { userSkillsByID[$0.id] ?? $0 }
            + skills.filter { !curatedIDs.contains($0.id) }
    }

    var skillCatalog: SkillCatalog {
        SkillCatalog(skills: availableSkills)
    }

    func refresh() {
        do {
            artefacts = try repository.fetchArtefacts()
            skills = try repository.fetchSkills()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func save(_ artefact: Artefact) {
        do {
            try repository.upsert(artefact)
            refresh()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func remove(_ artefact: Artefact) {
        do {
            try repository.delete(artefact)
            refresh()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func save(_ skill: Skill) {
        do {
            try repository.upsert(skill)
            refresh()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func remove(_ skill: Skill) {
        do {
            try repository.delete(skill)
            refresh()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    @discardableResult
    func createSkill(
        name: String,
        summary: String,
        instructions: String,
        targetKinds: Set<ArtefactKind> = Set(ArtefactKind.allCases),
        keywords: [String] = []
    ) -> Skill? {
        let skill = Skill(
            name: name,
            summary: summary,
            instructions: instructions,
            targetKinds: targetKinds,
            keywords: keywords
        )
        save(skill)
        return persistenceError == nil ? skill : nil
    }
}
