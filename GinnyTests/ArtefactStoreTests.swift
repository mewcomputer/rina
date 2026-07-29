import XCTest
@testable import Ginny

@MainActor
final class ArtefactStoreTests: XCTestCase {
    func testStoreLoadsAndSavesArtefactsAndSkills() throws {
        let repository = try ArtefactRepository(isStoredInMemoryOnly: true)
        let store = ArtefactStore(repository: repository)
        let artefact = Artefact(title: "Notes", kind: .document)
        let skill = Skill(
            name: "Notes",
            summary: "Keep notes clear.",
            instructions: "Use headings.",
            targetKinds: [.document]
        )

        store.save(artefact)
        store.save(skill)

        XCTAssertEqual(store.artefacts, [artefact])
        XCTAssertEqual(store.skills, [skill])
        XCTAssertTrue(store.availableSkills.contains { $0.name == "Frontend design" })
    }

    func testCreatingSkillPersistsAUserSkill() throws {
        let repository = try ArtefactRepository(isStoredInMemoryOnly: true)
        let store = ArtefactStore(repository: repository)

        let skill = store.createSkill(
            name: "Research notes",
            summary: "Capture sources clearly.",
            instructions: "Use a short source list.",
            targetKinds: [.document],
            keywords: ["research"]
        )

        XCTAssertEqual(skill?.name, "Research notes")
        XCTAssertEqual(store.skills.first?.name, "Research notes")
    }
}
