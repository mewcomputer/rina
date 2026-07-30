import Foundation

private let artefactWriteSchemaProperties: [String: JSONSchema] = [
    "title": JSONSchema(type: .string),
    "kind": JSONSchema(
        type: .string,
        enumValues: ArtefactKind.allCases.map(\.rawValue)
    ),
    "source": JSONSchema(type: .string),
    "renderedContent": JSONSchema(type: .string),
    "display_immediately": JSONSchema(type: .boolean),
    "metadata": JSONSchema.object(
        properties: [:],
        additionalProperties: .schema(JSONSchema(type: .string))
    )
]

struct ArtefactToolDetails: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: ArtefactKind
    let createdAt: String
    let revisionID: String
    let parentRevisionID: String?
    let source: String
    let renderedContent: String?
    let metadata: [String: String]
    let displayImmediately: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case kind
        case createdAt
        case revisionID
        case parentRevisionID
        case source
        case renderedContent
        case metadata
        case displayImmediately
    }

    init(
        id: String,
        title: String,
        kind: ArtefactKind,
        createdAt: String,
        revisionID: String,
        parentRevisionID: String?,
        source: String,
        renderedContent: String?,
        metadata: [String: String],
        displayImmediately: Bool
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.createdAt = createdAt
        self.revisionID = revisionID
        self.parentRevisionID = parentRevisionID
        self.source = source
        self.renderedContent = renderedContent
        self.metadata = metadata
        self.displayImmediately = displayImmediately
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(ArtefactKind.self, forKey: .kind)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        revisionID = try container.decode(String.self, forKey: .revisionID)
        parentRevisionID = try container.decodeIfPresent(String.self, forKey: .parentRevisionID)
        source = try container.decode(String.self, forKey: .source)
        renderedContent = try container.decodeIfPresent(String.self, forKey: .renderedContent)
        metadata = try container.decode([String: String].self, forKey: .metadata)
        displayImmediately = try container.decodeIfPresent(Bool.self, forKey: .displayImmediately) ?? false
    }
}

struct ArtefactToolSummary: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: ArtefactKind
    let createdAt: String
    let revisionID: String?
    let sourcePreview: String
}

struct ArtefactToolStore: Sendable {
    let fetchArtefacts: @MainActor @Sendable () throws -> [Artefact]
    let saveArtefact: @MainActor @Sendable (Artefact) throws -> Void

    @MainActor
    init(repository: ArtefactRepository) {
        fetchArtefacts = { try repository.fetchArtefacts() }
        saveArtefact = { artefact in try repository.upsert(artefact) }
    }
}

@MainActor
struct ArtefactToolSet: Sendable {
    private let store: ArtefactToolStore

    init(repository: ArtefactRepository) {
        store = ArtefactToolStore(repository: repository)
    }

    var tools: [any GinnyTool] {
        [
            ListArtefactsTool(store: store),
            ReadArtefactTool(store: store),
            CreateArtefactTool(store: store),
            UpdateArtefactTool(store: store),
            DisplayArtefactTool(store: store)
        ]
    }
}

struct ListArtefactsTool: GinnyTool {
    let store: ArtefactToolStore

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "list_artefacts",
            description: "Lists durable artefacts in the Ginny workspace. Use this before editing an existing artefact.",
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

        let decoded = try decodeArguments(
            Arguments.self,
            from: arguments,
            message: "list_artefacts expects optional query and kind fields."
        )
        let query = decoded.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artefacts = try await store.fetchArtefacts()
            .filter { artefact in
                guard decoded.kind == nil || artefact.kind == decoded.kind else {
                    return false
                }
                guard !query.isEmpty else { return true }
                let source = artefact.currentRevision?.source ?? ""
                return artefact.title.localizedCaseInsensitiveContains(query)
                    || artefact.kind.rawValue.localizedCaseInsensitiveContains(query)
                    || source.localizedCaseInsensitiveContains(query)
            }
            .map { artefact in
                ArtefactToolSummary(
                    id: artefact.id.rawValue.rawValue,
                    title: artefact.title,
                    kind: artefact.kind,
                    createdAt: artefact.createdAt.ISO8601Format(),
                    revisionID: artefact.currentRevisionID?.rawValue.rawValue,
                    sourcePreview: sourcePreview(for: artefact.currentRevision?.source)
                )
            }

        return try encode(artefacts)
    }
}

struct ReadArtefactTool: GinnyTool {
    let store: ArtefactToolStore

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "read_artefact",
            description: "Reads a durable artefact and one of its immutable revisions by ID.",
            inputSchema: .object(
                properties: [
                    "id": JSONSchema(type: .string),
                    "revisionID": JSONSchema(type: .string)
                ],
                required: ["id"]
            )
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .automatic }

    func execute(arguments: String) async throws -> String {
        struct Arguments: Decodable {
            let id: String
            let revisionID: String?
        }

        let decoded = try decodeArguments(
            Arguments.self,
            from: arguments,
            message: "read_artefact expects an artefact ID and an optional revision ID."
        )
        let artefact = try await findArtefact(id: decoded.id, using: store)
        let revision: ArtefactRevision
        if let revisionID = decoded.revisionID {
            revision = try findRevision(id: revisionID, in: artefact)
        } else if let currentRevision = artefact.currentRevision {
            revision = currentRevision
        } else {
            throw ToolExecutionError.invalidArguments("The artefact has no revisions.")
        }

        return try encode(details(for: artefact, revision: revision))
    }

}

struct CreateArtefactTool: GinnyTool {
    let store: ArtefactToolStore

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "create_artefact",
            description: "Creates and persists a new durable artefact with its first immutable revision. Choose inlineWeb for a compact visual embedded in chat; choose web for a standalone game, simulation, editor, dashboard, map, or rich interactive experience. Before creating a web or inlineWeb artefact, call read_skill with the relevant frontend skill and follow its instructions.",
            inputSchema: .object(
                properties: artefactWriteSchemaProperties,
                required: ["title", "kind", "source"]
            )
        )
    }

    func execute(arguments: String) async throws -> String {
        struct Arguments: Decodable {
            let title: String
            let kind: ArtefactKind
            let source: String
            let renderedContent: String?
            let displayImmediately: Bool?
            let metadata: [String: String]?

            private enum CodingKeys: String, CodingKey {
                case title
                case kind
                case source
                case renderedContent
                case displayImmediately = "display_immediately"
                case metadata
            }
        }

        let decoded = try decodeArguments(
            Arguments.self,
            from: arguments,
            message: "create_artefact expects title, kind, and source."
        )
        let networkPolicy = ArtefactNetworkPolicy(metadata: decoded.metadata ?? [:])
        guard networkPolicy.isValid else {
            throw ToolExecutionError.invalidArguments(
                "create_artefact networkOrigins must be a JSON array of up to eight exact HTTPS origins."
            )
        }
        let title = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ToolExecutionError.invalidArguments("create_artefact requires a non-empty title.")
        }
        guard !decoded.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("create_artefact requires non-empty source.")
        }

        var artefact = Artefact(
            title: title,
            kind: decoded.kind,
            metadata: decoded.metadata ?? [:]
        )
        let revisionID = artefact.checkpoint(
            source: decoded.source,
            renderedContent: decoded.renderedContent,
            metadata: decoded.metadata ?? [:]
        )
        try await store.saveArtefact(artefact)
        return try encode(
            details(
                for: artefact,
                revision: artefact.revision(id: revisionID)!,
                displayImmediately: decoded.displayImmediately ?? false
            )
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .requiresApproval }

    func approvalRequirement(for arguments: String) -> ToolApprovalRequirement {
        struct ApprovalArguments: Decodable {
            let kind: ArtefactKind?
            let source: String?
            let metadata: [String: String]?
        }

        guard let data = arguments.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ApprovalArguments.self, from: data)
        else {
            return approvalRequirement
        }

        let networkPolicy = ArtefactNetworkPolicy(metadata: decoded.metadata ?? [:])
        let requestsNetwork = decoded.source.map(ArtefactNetworkPolicy.requestsNetwork(in:)) == true
            || !networkPolicy.origins.isEmpty
        return decoded.kind == .inlineWeb && !requestsNetwork
            ? .automatic
            : approvalRequirement
    }
}

struct DisplayArtefactTool: GinnyTool {
    let store: ArtefactToolStore

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "display_artefact",
            description: "Surfaces an existing artefact in the current conversation. InlineWeb artefacts appear inline; web artefacts appear as a launch card that opens the full interactive surface; documents and code appear as compact cards.",
            inputSchema: .object(
                properties: [
                    "id": JSONSchema(type: .string),
                    "revisionID": JSONSchema(type: .string)
                ],
                required: ["id"]
            )
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .automatic }

    func execute(arguments: String) async throws -> String {
        struct Arguments: Decodable {
            let id: String
            let revisionID: String?
        }

        let decoded = try decodeArguments(
            Arguments.self,
            from: arguments,
            message: "display_artefact expects an artefact ID and an optional revision ID."
        )
        let artefact = try await findArtefact(id: decoded.id, using: store)
        let revision: ArtefactRevision
        if let revisionID = decoded.revisionID {
            revision = try findRevision(id: revisionID, in: artefact)
        } else if let currentRevision = artefact.currentRevision {
            revision = currentRevision
        } else {
            throw ToolExecutionError.invalidArguments("The artefact has no revisions.")
        }

        return try encode(details(for: artefact, revision: revision, displayImmediately: true))
    }
}

struct UpdateArtefactTool: GinnyTool {
    let store: ArtefactToolStore

    var definition: ProviderToolDefinition {
        ProviderToolDefinition(
            name: "update_artefact",
            description: "Creates a new immutable revision for an existing durable artefact.",
            inputSchema: .object(
                properties: artefactWriteSchemaProperties.merging(
                    ["id": JSONSchema(type: .string)],
                    uniquingKeysWith: { current, _ in current }
                ),
                required: ["id", "source"]
            )
        )
    }

    var approvalRequirement: ToolApprovalRequirement { .requiresApproval }

    func execute(arguments: String) async throws -> String {
        struct Arguments: Decodable {
            let id: String
            let title: String?
            let source: String
            let renderedContent: String?
            let metadata: [String: String]?
        }

        let decoded = try decodeArguments(
            Arguments.self,
            from: arguments,
            message: "update_artefact expects an artefact ID and source."
        )
        let networkPolicy = ArtefactNetworkPolicy(metadata: decoded.metadata ?? [:])
        guard networkPolicy.isValid else {
            throw ToolExecutionError.invalidArguments(
                "update_artefact networkOrigins must be a JSON array of up to eight exact HTTPS origins."
            )
        }
        let artefactID = try parseArtefactID(decoded.id)
        guard var artefact = try await store.fetchArtefacts().first(where: { $0.id == artefactID }) else {
            throw ToolExecutionError.invalidArguments("No artefact exists with ID \(decoded.id).")
        }
        guard !decoded.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("update_artefact requires non-empty source.")
        }
        if let title = decoded.title {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else {
                throw ToolExecutionError.invalidArguments("update_artefact requires a non-empty title when title is provided.")
            }
            artefact.setTitle(trimmedTitle)
        }

        let revisionID = artefact.checkpoint(
            source: decoded.source,
            renderedContent: decoded.renderedContent ?? artefact.currentRevision?.renderedContent,
            metadata: decoded.metadata ?? artefact.currentRevision?.metadata ?? [:]
        )
        try await store.saveArtefact(artefact)
        return try encode(details(for: artefact, revision: artefact.revision(id: revisionID)!))
    }
}

private func parseArtefactID(_ value: String) throws -> ArtefactID {
    guard let id = try? TID(string: value) else {
        throw ToolExecutionError.invalidArguments("Expected a valid artefact ID.")
    }
    return ArtefactID(rawValue: id)
}

private func findRevision(id: String, in artefact: Artefact) throws -> ArtefactRevision {
    guard let revisionID = try? TID(string: id),
          let revision = artefact.revision(id: RevisionID(rawValue: revisionID))
    else {
        throw ToolExecutionError.invalidArguments("No revision exists with ID \(id).")
    }
    return revision
}

private func findArtefact(id: String, using store: ArtefactToolStore) async throws -> Artefact {
    guard let artefactTID = try? TID(string: id) else {
        throw ToolExecutionError.invalidArguments("Expected a valid artefact ID.")
    }
    let artefactID = ArtefactID(rawValue: artefactTID)
    guard let artefact = try await store.fetchArtefacts().first(where: { $0.id == artefactID }) else {
        throw ToolExecutionError.invalidArguments("No artefact exists with ID \(id).")
    }
    return artefact
}

private func details(
    for artefact: Artefact,
    revision: ArtefactRevision,
    displayImmediately: Bool = false
) -> ArtefactToolDetails {
    ArtefactToolDetails(
        id: artefact.id.rawValue.rawValue,
        title: artefact.title,
        kind: artefact.kind,
        createdAt: artefact.createdAt.ISO8601Format(),
        revisionID: revision.id.rawValue.rawValue,
        parentRevisionID: revision.parentID?.rawValue.rawValue,
        source: revision.source,
        renderedContent: revision.renderedContent,
        metadata: revision.metadata,
        displayImmediately: displayImmediately
    )
}

private func sourcePreview(for source: String?) -> String {
    guard let source else { return "" }
    let preview = String(source.prefix(240))
    return source.count > 240 ? "\(preview)…" : preview
}

private func decodeArguments<T: Decodable>(
    _ type: T.Type,
    from arguments: String,
    message: String
) throws -> T {
    guard let data = arguments.data(using: .utf8) else {
        throw ToolExecutionError.invalidArguments(message)
    }
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw ToolExecutionError.invalidArguments(message)
    }
}

private func encode<T: Encodable>(_ value: T) throws -> String {
    try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
}
