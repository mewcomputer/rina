import XCTest
@testable import Ginny

final class SkillTests: XCTestCase {
    func testEditingSkillCreatesRevisionAndPreservesPreviousInstructions() throws {
        var skill = Skill(
            name: "Frontend design",
            summary: "Design accessible web artefacts.",
            instructions: "Use semantic tokens.",
            targetKinds: [.web, .inlineWeb],
            keywords: ["frontend", "web", "tailwind"]
        )
        let firstRevisionID = try XCTUnwrap(skill.currentRevision?.id)

        let secondRevisionID = skill.update(
            instructions: "Use semantic tokens and accessible states.",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(skill.currentRevision?.id, secondRevisionID)
        XCTAssertEqual(skill.currentRevision?.parentID, firstRevisionID)
        XCTAssertEqual(
            skill.revision(id: firstRevisionID)?.instructions,
            "Use semantic tokens."
        )
        XCTAssertEqual(
            skill.currentRevision?.instructions,
            "Use semantic tokens and accessible states."
        )
    }

    func testDiscoveryReturnsRelevantDiscoverableSkillsAndFiltersByArtefactKind() {
        let frontend = Skill(
            name: "Frontend design",
            summary: "Create clear and accessible web artefacts.",
            instructions: "Use shadcn semantic tokens.",
            targetKinds: [.web, .inlineWeb],
            keywords: ["frontend", "react", "tailwind"],
            isDiscoverable: true
        )
        let hidden = Skill(
            name: "Private notes",
            summary: "Personal instructions.",
            instructions: "Do not show this in discovery.",
            targetKinds: [.document],
            keywords: ["notes"],
            isDiscoverable: false
        )
        let catalog = SkillCatalog(skills: [hidden, frontend])

        let results = catalog.discover(query: "make a React Tailwind preview", for: .inlineWeb)

        XCTAssertEqual(results.map(\.id), [frontend.id])
        XCTAssertEqual(results.first?.name, "Frontend design")
    }

    func testCuratedSkillsContainFrontendDesignForWebArtefacts() {
        let frontend = CuratedSkills.all.first {
            $0.name == "Frontend design"
        }

        XCTAssertNotNil(frontend)
        XCTAssertTrue(frontend?.targetKinds.contains(.web) == true)
        XCTAssertTrue(frontend?.targetKinds.contains(.inlineWeb) == true)
        XCTAssertTrue(frontend?.isDiscoverable == true)
    }

    func testDiscoveryToolReturnsMatchingSkillDescriptors() async throws {
        let tool = DiscoverSkillsTool()

        let result = try await tool.execute(
            arguments: "{\"query\":\"react tailwind\",\"kind\":\"inlineWeb\"}"
        )
        let descriptors = try JSONDecoder().decode([SkillDescriptor].self, from: Data(result.utf8))

        XCTAssertEqual(descriptors.map(\.name), ["Frontend design"])
        XCTAssertEqual(tool.approvalRequirement, .automatic)
    }

    func testReadSkillToolReturnsCurrentInstructions() async throws {
        let tool = ReadSkillTool()

        let result = try await tool.execute(
            arguments: "{\"id\":\"ginny.frontend-design\"}"
        )
        let details = try JSONDecoder().decode(SkillDetails.self, from: Data(result.utf8))

        XCTAssertEqual(details.id, "ginny.frontend-design")
        XCTAssertTrue(details.instructions.contains("semantic color tokens"))
    }
}
