import XCTest
@testable import Ginny

@MainActor
final class ToolTests: XCTestCase {
    func testJSONSchemaEncodesAnObjectSchemaForProviderTools() throws {
        let schema = JSONSchema.object(
            properties: ["query": JSONSchema(type: .string)],
            required: ["query"]
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(schema)) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "object")
        XCTAssertEqual(object["required"] as? [String], ["query"])
        let querySchema = try XCTUnwrap(
            (object["properties"] as? [String: Any])?["query"] as? [String: Any]
        )
        XCTAssertEqual(querySchema["type"] as? String, "string")
        XCTAssertEqual(object["additionalProperties"] as? Bool, false)
    }

    func testCurrentTimeToolReturnsInjectedTime() async throws {
        let tool = CurrentTimeTool(now: { Date(timeIntervalSince1970: 0) })

        let result = try await tool.execute(arguments: "{}")

        XCTAssertEqual(result, "1970-01-01T00:00:00Z")
    }

    func testCurrentTimeToolRejectsArguments() async {
        let tool = CurrentTimeTool(now: { Date(timeIntervalSince1970: 0) })

        do {
            _ = try await tool.execute(arguments: "{\"timezone\":\"UTC\"}")
            XCTFail("Expected invalid arguments")
        } catch {
            XCTAssertEqual(
                error as? ToolExecutionError,
                .invalidArguments("current_time does not accept arguments.")
            )
        }
    }

    func testToolRegistryReportsUnknownTools() async {
        let registry = ToolRegistry(tools: [])

        do {
            _ = try await registry.execute(name: "missing", arguments: "{}")
            XCTFail("Expected unknown tool")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .unknownTool("missing"))
        }
    }

    func testToolRegistryExposesExplicitApprovalRequirements() {
        let registry = ToolRegistry(tools: [RequiresApprovalTool()])

        XCTAssertEqual(
            registry.approvalRequirement(for: "requires_approval"),
            .requiresApproval
        )
        XCTAssertEqual(
            ToolRegistry(tools: [CurrentTimeTool()])
                .approvalRequirement(for: "current_time"),
            .automatic
        )
    }

    func testToolRegistryRefreshesSkillDiscoveryWithoutReplacingOtherTools() {
        var registry = ToolRegistry(tools: [CurrentTimeTool()])
        let skill = Skill(
            name: "Writing polish",
            summary: "Improve writing.",
            instructions: "Use concrete verbs.",
            targetKinds: [.document],
            keywords: ["writing"]
        )

        registry.updateSkillCatalog(SkillCatalog(skills: [skill]))

        XCTAssertEqual(
            registry.tools.map { $0.definition.name },
            ["current_time", "discover_skills", "read_skill"]
        )
    }

    func testArtefactToolsCreateReadListAndCheckpointRevisions() async throws {
        let repository = try ArtefactRepository(isStoredInMemoryOnly: true)
        let registry = ToolRegistry(tools: ArtefactToolSet(repository: repository).tools)

        let createdJSON = try await registry.execute(
            name: "create_artefact",
            arguments: """
            {"title":"Save button","kind":"inlineWeb","source":"<button>Save</button>","renderedContent":"<button>Save</button>"}
            """
        )
        let created = try JSONDecoder().decode(ArtefactToolDetails.self, from: Data(createdJSON.utf8))
        XCTAssertEqual(created.title, "Save button")
        XCTAssertEqual(created.kind, .inlineWeb)
        XCTAssertEqual(registry.approvalRequirement(for: "create_artefact"), .requiresApproval)

        let listedJSON = try await registry.execute(
            name: "list_artefacts",
            arguments: "{\"query\":\"save button\"}"
        )
        let listed = try JSONDecoder().decode([ArtefactToolSummary].self, from: Data(listedJSON.utf8))
        XCTAssertEqual(listed.map(\.id), [created.id])

        let readJSON = try await registry.execute(
            name: "read_artefact",
            arguments: "{\"id\":\"\(created.id)\"}"
        )
        let read = try JSONDecoder().decode(ArtefactToolDetails.self, from: Data(readJSON.utf8))
        XCTAssertEqual(read.source, "<button>Save</button>")

        let updatedJSON = try await registry.execute(
            name: "update_artefact",
            arguments: """
            {"id":"\(created.id)","source":"<button>Save changes</button>"}
            """
        )
        let updated = try JSONDecoder().decode(ArtefactToolDetails.self, from: Data(updatedJSON.utf8))
        XCTAssertNotEqual(updated.revisionID, created.revisionID)
        XCTAssertEqual(updated.parentRevisionID, created.revisionID)
        XCTAssertEqual(updated.source, "<button>Save changes</button>")
        XCTAssertEqual(registry.approvalRequirement(for: "update_artefact"), .requiresApproval)
    }

    func testInlineWebCreationIsAutomaticButDurableDocumentCreationRequiresApproval() throws {
        let repository = try ArtefactRepository(isStoredInMemoryOnly: true)
        let registry = ToolRegistry(tools: ArtefactToolSet(repository: repository).tools)

        XCTAssertEqual(
            registry.approvalRequirement(
                for: "create_artefact",
                arguments: "{\"kind\":\"inlineWeb\"}"
            ),
            .automatic
        )
        XCTAssertEqual(
            registry.approvalRequirement(
                for: "create_artefact",
                arguments: "{\"kind\":\"document\"}"
            ),
            .requiresApproval
        )
        XCTAssertEqual(
            registry.approvalRequirement(for: "create_artefact"),
            .requiresApproval
        )
    }
}

private struct RequiresApprovalTool: GinnyTool {
    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "requires_approval",
            description: "A fixture tool that requires explicit user approval.",
            inputSchema: .object(properties: [:])
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .requiresApproval }

    func execute(arguments: String) async throws -> String {
        "approved"
    }
}
