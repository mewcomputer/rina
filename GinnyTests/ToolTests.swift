import XCTest
@testable import Ginny

final class ToolTests: XCTestCase {
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
}

private struct RequiresApprovalTool: GinnyTool {
    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "requires_approval",
            description: "A fixture tool that requires explicit user approval.",
            inputSchema: "{\"type\":\"object\"}"
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .requiresApproval }

    func execute(arguments: String) async throws -> String {
        "approved"
    }
}
