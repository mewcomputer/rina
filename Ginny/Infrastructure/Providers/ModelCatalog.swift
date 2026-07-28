import Foundation

struct ProviderModel: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let description: String?
    let capabilities: ModelCapabilities

    init(
        id: String,
        displayName: String,
        description: String? = nil,
        capabilities: ModelCapabilities = ModelCapabilities()
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.capabilities = capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        description = try container.decodeIfPresent(String.self, forKey: .description)
        capabilities = try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities)
            ?? ModelCapabilities()
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case description
        case capabilities
    }
}

struct ModelCapabilities: Decodable, Equatable, Sendable {
    let maxCompletionTokens: Int?
    let recommendedMaxTokens: Int?
    let contextWindow: Int?
    let supportsVision: String?
    let supportsTools: Bool?
    let reasoning: ModelReasoningCapabilities?

    init(
        maxCompletionTokens: Int? = nil,
        recommendedMaxTokens: Int? = nil,
        contextWindow: Int? = nil,
        supportsVision: String? = nil,
        supportsTools: Bool? = nil,
        reasoning: ModelReasoningCapabilities? = nil
    ) {
        self.maxCompletionTokens = maxCompletionTokens
        self.recommendedMaxTokens = recommendedMaxTokens
        self.contextWindow = contextWindow
        self.supportsVision = supportsVision
        self.supportsTools = supportsTools
        self.reasoning = reasoning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxCompletionTokens = try container.decodeIfPresent(Int.self, forKey: .maxCompletionTokens)
        recommendedMaxTokens = try container.decodeIfPresent(Int.self, forKey: .recommendedMaxTokens)
        contextWindow = try container.decodeIfPresent(Int.self, forKey: .contextWindow)
        supportsTools = try container.decodeIfPresent(Bool.self, forKey: .supportsTools)
        reasoning = try container.decodeIfPresent(ModelReasoningCapabilities.self, forKey: .reasoning)

        if let value = try? container.decode(Bool.self, forKey: .supportsVision) {
            supportsVision = String(value)
        } else {
            supportsVision = try container.decodeIfPresent(String.self, forKey: .supportsVision)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case maxCompletionTokens = "max_completion_tokens"
        case recommendedMaxTokens = "recommended_max_tokens"
        case contextWindow = "context_window"
        case supportsVision = "supports_vision"
        case supportsTools = "supports_tools"
        case reasoning
    }
}

struct ModelReasoningCapabilities: Decodable, Equatable, Sendable {
    let supported: Bool?
    let canDisable: Bool?
    let levels: [String]
    let defaultLevel: String?

    init(
        supported: Bool? = nil,
        canDisable: Bool? = nil,
        levels: [String] = [],
        defaultLevel: String? = nil
    ) {
        self.supported = supported
        self.canDisable = canDisable
        self.levels = levels
        self.defaultLevel = defaultLevel
    }

    private enum CodingKeys: String, CodingKey {
        case supported
        case canDisable = "can_disable"
        case levels
        case defaultLevel = "default_level"
    }
}

protocol ModelCatalogProviding: Sendable {
    func models(for provider: ProviderID, baseURL: URL) async throws -> [ProviderModel]
}

struct URLSessionModelCatalog: ModelCatalogProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func models(for provider: ProviderID, baseURL: URL) async throws -> [ProviderModel] {
        guard provider == .umans else {
            throw ProviderError.invalidConfiguration("This provider does not publish a model catalog.")
        }

        var request = URLRequest(url: provider.catalogURL(for: baseURL))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.httpStatus(httpResponse.statusCode, message: nil)
        }

        do {
            let catalog = try JSONDecoder().decode([String: ProviderModel].self, from: data)
            return catalog.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        } catch {
            throw ProviderError.invalidResponse
        }
    }
}

extension ProviderID {
    func messageEndpoint(for baseURL: URL) -> URL {
        switch self {
        case .umans:
            baseURL.appendingProviderPath("v1/messages")
        case .openAICompatible:
            baseURL.appendingProviderPath("v1/chat/completions")
        }
    }

    func catalogURL(for baseURL: URL) -> URL {
        baseURL.appendingProviderPath("v1/models/info")
    }
}

private extension URL {
    func appendingProviderPath(_ path: String) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = self.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = "/v1"
        if basePath.hasSuffix(suffix), normalizedPath.hasPrefix("v1/") {
            return appendingPathComponent(String(normalizedPath.dropFirst(3)))
        }
        return appendingPathComponent(normalizedPath)
    }
}
