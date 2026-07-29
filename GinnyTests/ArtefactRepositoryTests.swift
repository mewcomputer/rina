import XCTest
@testable import Ginny

@MainActor
final class ArtefactRepositoryTests: XCTestCase {
    func testConversationAndArtefactRepositoriesCanShareOneContainer() throws {
        let container = try GinnyPersistence.makeContainer(isStoredInMemoryOnly: true)
        let conversationRepository = ConversationRepository(container: container)
        let artefactRepository = ArtefactRepository(container: container)
        let conversation = Conversation(
            messages: [Message.user("Keep this session")],
            generationState: .completed
        )
        var artefact = Artefact(title: "Keep this artefact", kind: .document)
        _ = artefact.checkpoint(source: "Durable content")

        try conversationRepository.upsert(conversation)
        try artefactRepository.upsert(artefact)

        XCTAssertEqual(try conversationRepository.fetch(), [conversation])
        XCTAssertEqual(try artefactRepository.fetchArtefacts(), [artefact])
    }

    func testRepositoryRoundTripsArtefactRevisionsAndPreview() throws {
        let repository = try ArtefactRepository(isStoredInMemoryOnly: true)
        var artefact = Artefact(title: "Widget", kind: .inlineWeb)
        _ = artefact.checkpoint(
            source: "<button>Save</button>",
            renderedContent: "<button class=\"primary\">Save</button>",
            metadata: ["framework": "react"]
        )
        _ = artefact.checkpoint(
            source: "<button>Save changes</button>",
            renderedContent: "<button class=\"primary\">Save changes</button>",
            metadata: ["framework": "react", "styling": "tailwind"]
        )

        try repository.upsert(artefact)

        let restored = try XCTUnwrap(try repository.fetchArtefacts().first)
        XCTAssertEqual(restored, artefact)
        XCTAssertEqual(restored.currentRevision?.renderedContent, "<button class=\"primary\">Save changes</button>")
        XCTAssertEqual(restored.revisions.count, 2)
    }

    func testRepositoryRoundTripsUserSkillAndKeepsRevisionHistory() throws {
        let repository = try ArtefactRepository(isStoredInMemoryOnly: true)
        var skill = Skill(
            name: "Writing polish",
            summary: "Improve clarity.",
            instructions: "Use short sentences.",
            targetKinds: [.document],
            keywords: ["writing", "clarity"]
        )
        _ = skill.update(instructions: "Use short sentences and concrete verbs.")

        try repository.upsert(skill)

        let restored = try XCTUnwrap(try repository.fetchSkills().first)
        XCTAssertEqual(restored, skill)
        XCTAssertEqual(restored.revisions.count, 2)
        XCTAssertFalse(restored.isBuiltIn)
    }

    func testDeletingArtefactDoesNotDeleteIndependentSkill() throws {
        let repository = try ArtefactRepository(isStoredInMemoryOnly: true)
        let artefact = Artefact(title: "Notes", kind: .document)
        let skill = Skill(
            name: "Notes",
            summary: "A skill",
            instructions: "Keep it clear.",
            targetKinds: [.document]
        )

        try repository.upsert(artefact)
        try repository.upsert(skill)
        try repository.delete(artefact)

        XCTAssertTrue(try repository.fetchArtefacts().isEmpty)
        XCTAssertEqual(try repository.fetchSkills(), [skill])
    }
}
