import Foundation

/// A small local snapshot of the public model metadata shipped with Codex.
///
/// The live catalog is preferred. This fallback keeps the provider usable when
/// the ChatGPT catalog endpoint is unavailable or changes shape. Refresh this
/// snapshot from:
/// https://github.com/openai/codex/blob/main/codex-rs/models-manager/models.json
struct CodexModelsManifest: Decodable, Sendable {
    let models: [CodexManifestModel]

    var providerModels: [ProviderModel] {
        models
            .filter { $0.supportedInAPI && $0.visibility != "hidden" }
            .compactMap(\.providerModel)
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    static let fallback = CodexModelsManifest(models: [
        CodexManifestModel(
            slug: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            description: "Latest frontier agentic coding model.",
            contextWindow: 272_000,
            defaultReasoningLevel: "low",
            supportedReasoningLevels: ["low", "medium", "high", "xhigh", "max", "ultra"],
            supportedInAPI: true,
            visibility: "list"
        ),
        CodexManifestModel(
            slug: "gpt-5.6-terra",
            displayName: "GPT-5.6-Terra",
            description: "Frontier agentic coding model.",
            contextWindow: 272_000,
            defaultReasoningLevel: "medium",
            supportedReasoningLevels: ["low", "medium", "high", "xhigh", "max", "ultra"],
            supportedInAPI: true,
            visibility: "list"
        ),
        CodexManifestModel(
            slug: "gpt-5.6-luna",
            displayName: "GPT-5.6-Luna",
            description: "Frontier coding model.",
            contextWindow: 272_000,
            defaultReasoningLevel: "medium",
            supportedReasoningLevels: ["low", "medium", "high", "xhigh", "max"],
            supportedInAPI: true,
            visibility: "list"
        ),
        CodexManifestModel(
            slug: "gpt-5.5",
            displayName: "GPT-5.5",
            description: "General-purpose coding model.",
            contextWindow: 272_000,
            defaultReasoningLevel: "medium",
            supportedReasoningLevels: ["low", "medium", "high", "xhigh"],
            supportedInAPI: true,
            visibility: "list"
        ),
        CodexManifestModel(
            slug: "gpt-5.2",
            displayName: "GPT-5.2",
            description: "General-purpose coding model.",
            contextWindow: 272_000,
            defaultReasoningLevel: "medium",
            supportedReasoningLevels: ["low", "medium", "high", "xhigh"],
            supportedInAPI: true,
            visibility: "list"
        ),
    ])
}

struct CodexManifestModel: Decodable, Sendable {
    let slug: String
    let displayName: String
    let description: String?
    let contextWindow: Int?
    let defaultReasoningLevel: String?
    let supportedReasoningLevels: [String]
    let supportedInAPI: Bool
    let visibility: String?

    init(
        slug: String,
        displayName: String,
        description: String?,
        contextWindow: Int?,
        defaultReasoningLevel: String?,
        supportedReasoningLevels: [String],
        supportedInAPI: Bool,
        visibility: String?
    ) {
        self.slug = slug
        self.displayName = displayName
        self.description = description
        self.contextWindow = contextWindow
        self.defaultReasoningLevel = defaultReasoningLevel
        self.supportedReasoningLevels = supportedReasoningLevels
        self.supportedInAPI = supportedInAPI
        self.visibility = visibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? slug
        description = try container.decodeIfPresent(String.self, forKey: .description)
        contextWindow = try container.decodeIfPresent(Int.self, forKey: .contextWindow)
        defaultReasoningLevel = try container.decodeIfPresent(
            String.self,
            forKey: .defaultReasoningLevel
        )
        let reasoningLevels = try container.decodeIfPresent(
            [CodexReasoningLevel].self,
            forKey: .supportedReasoningLevels
        ) ?? []
        supportedReasoningLevels = reasoningLevels.map(\.effort)
        supportedInAPI = try container.decodeIfPresent(Bool.self, forKey: .supportedInAPI) ?? true
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
    }

    var providerModel: ProviderModel? {
        guard !slug.isEmpty else { return nil }
        let levels = supportedReasoningLevels.filter { ThinkingLevel(rawValue: $0) != nil }
        let reasoning = levels.isEmpty
            ? nil
            : ModelReasoningCapabilities(
                supported: true,
                canDisable: false,
                levels: levels,
                defaultLevel: defaultReasoningLevel
            )
        return ProviderModel(
            id: slug,
            displayName: displayName,
            description: description,
            capabilities: ModelCapabilities(
                contextWindow: contextWindow,
                supportsTools: true,
                reasoning: reasoning
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case description
        case contextWindow = "context_window"
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
        case supportedInAPI = "supported_in_api"
        case visibility
    }
}

private struct CodexReasoningLevel: Decodable, Sendable {
    let effort: String
}
