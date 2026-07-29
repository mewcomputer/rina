import Foundation

enum ToolApprovalRequirement: String, Codable, Equatable, Sendable {
    case automatic
    case requiresApproval
}

struct ToolApprovalRequest: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

protocol GinnyTool: Sendable {
    var definition: ProviderToolDefinition { get }
    var approvalRequirement: ToolApprovalRequirement { get }

    func execute(arguments: String) async throws -> String
}

extension GinnyTool {
    var approvalRequirement: ToolApprovalRequirement { .requiresApproval }
}

enum ToolExecutionError: Error, Equatable, Sendable {
    case unknownTool(String)
    case invalidArguments(String)
}

struct ToolRegistry: Sendable {
    private(set) var tools: [any GinnyTool]

    init(tools: [any GinnyTool] = [
        CurrentTimeTool(),
        DiscoverSkillsTool(),
        ReadSkillTool()
    ]) {
        self.tools = tools
    }

    var definitions: [ProviderToolDefinition] {
        tools.map(\.definition)
    }

    mutating func updateSkillCatalog(_ catalog: SkillCatalog) {
        tools.removeAll {
            $0.definition.name == "discover_skills"
                || $0.definition.name == "read_skill"
        }
        tools.append(DiscoverSkillsTool(catalog: catalog))
        tools.append(ReadSkillTool(catalog: catalog))
    }

    func approvalRequirement(for name: String) -> ToolApprovalRequirement? {
        tools.first(where: { $0.definition.name == name })?.approvalRequirement
    }

    func execute(name: String, arguments: String) async throws -> String {
        guard let tool = tools.first(where: { $0.definition.name == name }) else {
            throw ToolExecutionError.unknownTool(name)
        }

        return try await tool.execute(arguments: arguments)
    }
}

struct CurrentTimeTool: GinnyTool {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "current_time",
            description: "Returns the current date and time in ISO 8601 format.",
            inputSchema: "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}"
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .automatic }

    func execute(arguments: String) async throws -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || trimmed == "{}" else {
            throw ToolExecutionError.invalidArguments("current_time does not accept arguments.")
        }

        return now().ISO8601Format()
    }
}
