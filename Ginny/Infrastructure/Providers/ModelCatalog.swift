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
    func models(
        for provider: ProviderID,
        baseURL: URL,
        credential: String?
    ) async throws -> [ProviderModel]
}

struct URLSessionModelCatalog: ModelCatalogProviding {
    private let session: URLSession
    private let cache: ModelCatalogCache

    init(
        session: URLSession = .shared,
        cacheDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.cache = ModelCatalogCache(defaults: cacheDefaults)
    }

    func models(
        for provider: ProviderID,
        baseURL: URL,
        credential: String?
    ) async throws -> [ProviderModel] {
        if let knownModels = provider.knownModels {
            return knownModels
        }

        if provider == .codex,
           !CodexOAuthService.isOfficialBackendURL(baseURL)
        {
            throw ProviderError.invalidConfiguration(
                "Codex only supports the official ChatGPT endpoint."
            )
        }

        var request = URLRequest(url: provider.catalogURL(for: baseURL))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if provider != .umans && provider != .codex {
            guard let credential, !credential.isEmpty else {
                throw ProviderError.missingCredential
            }
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        } else if let credential, !credential.isEmpty {
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        } else if provider == .codex {
            return CodexModelsManifest.fallback.providerModels
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if provider == .umans,
               let cachedModels = cachedUmansModels()
            {
                return cachedModels
            }
            if provider == .codex {
                return cachedCodexModels(for: baseURL) ?? CodexModelsManifest.fallback.providerModels
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            if provider == .umans,
               let cachedModels = cachedUmansModels()
            {
                return cachedModels
            }
            if provider == .codex {
                return cachedCodexModels(for: baseURL) ?? CodexModelsManifest.fallback.providerModels
            }
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = ProviderError.httpStatus(httpResponse.statusCode, message: nil)
            if provider == .umans,
               let cachedModels = cachedUmansModels()
            {
                return cachedModels
            }
            if provider == .codex, httpResponse.statusCode == 401 {
                throw error
            }
            if provider == .codex {
                return cachedCodexModels(for: baseURL) ?? CodexModelsManifest.fallback.providerModels
            }
            throw error
        }

        do {
            let decoder = JSONDecoder()
            let models: [ProviderModel]
            if provider == .umans {
                models = Array(try decoder.decode([String: ProviderModel].self, from: data).values)
                cache.defaults.set(data, forKey: Self.umansCacheKey)
            } else if provider == .codex {
                models = try decoder.decode(CodexModelsManifest.self, from: data).providerModels
                cache.defaults.set(data, forKey: Self.codexCacheKey(for: baseURL))
            } else {
                let response = try decoder.decode(OpenAIModelListResponse.self, from: data)
                models = response.data.map {
                    ProviderModel(id: $0.id, displayName: $0.id)
                }
            }
            return models.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        } catch {
            if provider == .umans,
               let cachedModels = cachedUmansModels()
            {
                return cachedModels
            }
            if provider == .codex {
                return cachedCodexModels(for: baseURL) ?? CodexModelsManifest.fallback.providerModels
            }
            throw ProviderError.invalidResponse
        }
    }

    private func cachedUmansModels() -> [ProviderModel]? {
        guard let data = cache.defaults.data(forKey: Self.umansCacheKey) else {
            return nil
        }
        return try? JSONDecoder()
            .decode([String: ProviderModel].self, from: data)
            .values
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private func cachedCodexModels(for baseURL: URL) -> [ProviderModel]? {
        guard let data = cache.defaults.data(forKey: Self.codexCacheKey(for: baseURL)) else {
            return nil
        }
        return try? JSONDecoder()
            .decode(CodexModelsManifest.self, from: data)
            .providerModels
    }

    private static let umansCacheKey = "provider.umans.modelCatalog"
    private static func codexCacheKey(for baseURL: URL) -> String {
        "provider.codex.modelCatalog.\(baseURL.absoluteString.lowercased())"
    }
}

private final class ModelCatalogCache: @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
}

extension ProviderID {
    func messageEndpoint(for baseURL: URL) -> URL {
        switch self {
        case .umans:
            baseURL.appendingProviderPath("v1/messages")
        case .kimi, .kimiCode, .openAICompatible:
            baseURL.appendingProviderPath("v1/chat/completions")
        case .codex:
            baseURL.appendingProviderPath("responses")
        }
    }

    func catalogURL(for baseURL: URL) -> URL {
        switch self {
        case .umans:
            Self.umansModelCatalogURL
        case .kimi, .kimiCode, .openAICompatible:
            baseURL.appendingProviderPath("v1/models")
        case .codex:
            baseURL.appendingProviderPath("models")
        }
    }

    var knownModels: [ProviderModel]? {
        switch self {
        case .kimiCode:
            [
                ProviderModel(id: "k3", displayName: "K3"),
                ProviderModel(id: "k3-256k", displayName: "K3 256K"),
                ProviderModel(id: "kimi-for-coding", displayName: "Kimi for Coding"),
                ProviderModel(
                    id: "kimi-for-coding-highspeed",
                    displayName: "Kimi for Coding Highspeed"
                )
            ]
        case .umans, .kimi, .openAICompatible, .codex:
            nil
        }
    }

    private static let umansModelCatalogURL = URL(
        string: "https://api.code.umans.ai/v1/models/info"
    )!
}

private struct OpenAIModelListResponse: Decodable {
    let data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    let id: String
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
