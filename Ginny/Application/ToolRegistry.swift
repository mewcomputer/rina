import Foundation

protocol GinnyTool: Sendable {
    var definition: ProviderToolDefinition { get }

    func execute(arguments: String) async throws -> String
}

enum ToolExecutionError: Error, Equatable, Sendable {
    case unknownTool(String)
    case invalidArguments(String)
}

struct ToolRegistry: Sendable {
    let tools: [any GinnyTool]

    init(tools: [any GinnyTool] = [CurrentTimeTool()]) {
        self.tools = tools
    }

    var definitions: [ProviderToolDefinition] {
        tools.map(\.definition)
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

    func execute(arguments: String) async throws -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || trimmed == "{}" else {
            throw ToolExecutionError.invalidArguments("current_time does not accept arguments.")
        }

        return now().ISO8601Format()
    }
}
