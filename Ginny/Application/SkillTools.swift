import Foundation

struct SkillDetails: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let instructions: String
    let targetKinds: Set<ArtefactKind>
    let keywords: [String]
    let revisionID: RevisionID
}

struct DiscoverSkillsTool: GinnyTool {
    let catalog: SkillCatalog

    init(catalog: SkillCatalog = SkillCatalog()) {
        self.catalog = catalog
    }

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "discover_skills",
            description: "Finds relevant local skills. E.g. if you want to find a web search skill, or a web design skill.",
            inputSchema: .object(
                properties: [
                    "query": JSONSchema(type: .string),
                    "kind": JSONSchema(
                        type: .string,
                        enumValues: ArtefactKind.allCases.map(\.rawValue)
                    )
                ]
            )
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .automatic }

    func execute(arguments: String) async throws -> String {
        struct Arguments: Decodable {
            let query: String?
            let kind: ArtefactKind?
        }

        guard let data = arguments.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Arguments.self, from: data)
        else {
            throw ToolExecutionError.invalidArguments(
                "discover_skills expects an object with optional query and kind fields."
            )
        }

        let descriptors = catalog.discover(query: decoded.query ?? "", for: decoded.kind)
        return try String(decoding: JSONEncoder().encode(descriptors), as: UTF8.self)
    }
}

struct ReadSkillTool: GinnyTool {
    let catalog: SkillCatalog

    init(catalog: SkillCatalog = SkillCatalog()) {
        self.catalog = catalog
    }

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "read_skill",
            description: "Loads the current instructions for a local skill by ID.",
            inputSchema: .object(
                properties: ["id": JSONSchema(type: .string)],
                required: ["id"]
            )
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .automatic }

    func execute(arguments: String) async throws -> String {
        struct Arguments: Decodable {
            let id: String
        }

        guard let data = arguments.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Arguments.self, from: data),
              let skill = catalog.skill(id: decoded.id),
              let revision = skill.currentRevision
        else {
            throw ToolExecutionError.invalidArguments(
                "read_skill expects the ID of an available skill."
            )
        }

        let details = SkillDetails(
            id: skill.id,
            name: skill.name,
            summary: skill.summary,
            instructions: revision.instructions,
            targetKinds: skill.targetKinds,
            keywords: skill.keywords,
            revisionID: revision.id
        )
        return try String(decoding: JSONEncoder().encode(details), as: UTF8.self)
    }
}
