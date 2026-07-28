import Combine
import Foundation

@MainActor
final class ProviderSettings: ObservableObject {
    static let defaultEndpoint = "https://api.code.umans.ai"
    static let credentialID = "umans-api-key"

    @Published var provider: ProviderID
    @Published var endpointText: String
    @Published var modelText: String
    @Published var credentialText: String
    @Published var thinkingLevel: ThinkingLevel = .high
    @Published private(set) var availableModels: [ProviderModel] = []
    @Published private(set) var isLoadingModels = false
    @Published private(set) var catalogMessage: String?
    @Published private(set) var validationMessage: String?

    private let defaults: UserDefaults
    private let credentialStore: any CredentialStore
    private let modelCatalog: any ModelCatalogProviding

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        modelCatalog: any ModelCatalogProviding = URLSessionModelCatalog()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.modelCatalog = modelCatalog
        let storedProvider = defaults.string(forKey: "provider.id")
        let selectedProvider = ProviderID(rawValue: storedProvider ?? "") ?? .umans
        provider = selectedProvider
        let storedBaseURL = defaults.string(forKey: selectedProvider.baseURLKey)
            ?? (storedProvider == nil ? nil : defaults.string(forKey: "provider.endpoint"))
        let storedModel = defaults.string(forKey: selectedProvider.modelKey)
            ?? (storedProvider == nil ? nil : defaults.string(forKey: "provider.model"))
        endpointText = Self.normalizedBaseURLText(storedBaseURL, provider: selectedProvider)
            ?? selectedProvider.defaultBaseURL
        modelText = storedModel ?? selectedProvider.defaultModel
        credentialText = (try? credentialStore.credential(for: selectedProvider.credentialID)) ?? ""
        thinkingLevel = Self.storedThinkingLevel(
            defaults: defaults,
            provider: selectedProvider,
            model: modelText
        )
    }

    var configuration: ProviderConfiguration? {
        guard let baseURL = validBaseURL,
              !modelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return ProviderConfiguration(
            provider: provider,
            endpoint: provider.messageEndpoint(for: baseURL),
            model: modelText.trimmingCharacters(in: .whitespacesAndNewlines),
            credentialID: provider.credentialID,
            thinkingLevel: thinkingOptions.contains(thinkingLevel) ? thinkingLevel : nil
        )
    }

    var thinkingOptions: [ThinkingLevel] {
        guard provider == .kimiCode else { return [] }
        if ["kimi-for-coding", "kimi-for-coding-highspeed"].contains(modelText) {
            return [.off, .on]
        }
        if ["k3", "k3-256k"].contains(modelText) {
            return [.off, .low, .high, .max]
        }
        return []
    }

    var validBaseURL: URL? {
        let endpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint),
              url.scheme == "https"
                || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? ""))
        else {
            return nil
        }
        return Self.normalizedBaseURL(url, provider: provider)
    }

    func selectProvider(_ provider: ProviderID) {
        self.provider = provider
        endpointText = defaults.string(forKey: provider.baseURLKey) ?? provider.defaultBaseURL
        modelText = defaults.string(forKey: provider.modelKey) ?? provider.defaultModel
        credentialText = (try? credentialStore.credential(for: provider.credentialID)) ?? ""
        thinkingLevel = Self.storedThinkingLevel(
            defaults: defaults,
            provider: provider,
            model: modelText
        )
        availableModels = []
        catalogMessage = nil
        validationMessage = nil
    }

    func selectProviderAndRefresh(_ provider: ProviderID) async {
        selectProvider(provider)
        await refreshModels()
    }

    func refreshModels() async {
        guard let baseURL = validBaseURL else {
            catalogMessage = "Enter a valid base URL before refreshing models."
            return
        }

        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let credential = try? credentialStore.credential(for: provider.credentialID)
            availableModels = try await modelCatalog.models(
                for: provider,
                baseURL: baseURL,
                credential: credential ?? nil
            )
            if !availableModels.contains(where: { $0.id == modelText }) {
                selectModel(
                    availableModels.first(where: { $0.id == "umans-coder" })?.id
                    ?? availableModels.first?.id
                    ?? modelText
                )
            }
            catalogMessage = nil
        } catch ProviderError.missingCredential {
            availableModels = []
            catalogMessage = "Add an API key to load models."
        } catch {
            availableModels = []
            catalogMessage = "Models could not be refreshed."
        }
    }

    func selectModel(_ model: String) {
        modelText = model
        thinkingLevel = Self.storedThinkingLevel(
            defaults: defaults,
            provider: provider,
            model: model
        )
    }

    func selectThinkingLevel(_ level: ThinkingLevel) {
        guard thinkingOptions.contains(level) else { return }
        thinkingLevel = level
        defaults.set(
            level.rawValue,
            forKey: Self.thinkingLevelKey(for: provider, model: modelText)
        )
    }

    @discardableResult
    func save() -> Bool {
        guard let baseURL = validBaseURL else {
            validationMessage = "Use HTTPS, or a localhost endpoint for local development."
            return false
        }
        let endpoint = baseURL.absoluteString
        let model = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            validationMessage = "Enter the model name."
            return false
        }
        let credential = credentialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
            validationMessage = "Enter a provider credential."
            return false
        }

        do {
            try credentialStore.save(credential, for: provider.credentialID)
        } catch {
            validationMessage = "The credential could not be saved securely."
            return false
        }

        defaults.set(provider.rawValue, forKey: "provider.id")
        defaults.set(endpoint, forKey: provider.baseURLKey)
        defaults.set(model, forKey: provider.modelKey)
        defaults.set(endpoint, forKey: "provider.endpoint")
        defaults.set(model, forKey: "provider.model")
        endpointText = endpoint
        modelText = model
        credentialText = credential
        validationMessage = nil
        return true
    }

    private static func normalizedBaseURLText(
        _ value: String?,
        provider: ProviderID
    ) -> String? {
        guard let value,
              let url = URL(string: value)
        else {
            return nil
        }
        return normalizedBaseURL(url, provider: provider).absoluteString
    }

    private static func normalizedBaseURL(_ url: URL, provider: ProviderID) -> URL {
        let endpointSuffix: String
        switch provider {
        case .umans:
            endpointSuffix = "/v1/messages"
        case .kimi, .kimiCode, .openAICompatible:
            endpointSuffix = "/v1/chat/completions"
        }

        guard url.path.hasSuffix(endpointSuffix) else {
            return url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = String(url.path.dropLast(endpointSuffix.count))
        return components?.url ?? url
    }

    private static func storedThinkingLevel(
        defaults: UserDefaults,
        provider: ProviderID,
        model: String
    ) -> ThinkingLevel {
        guard let rawValue = defaults.string(forKey: thinkingLevelKey(for: provider, model: model)),
              let level = ThinkingLevel(rawValue: rawValue)
        else {
            return defaultThinkingLevel(for: provider, model: model)
        }
        return level
    }

    private static func defaultThinkingLevel(for provider: ProviderID, model: String) -> ThinkingLevel {
        if provider == .kimiCode,
           ["kimi-for-coding", "kimi-for-coding-highspeed"].contains(model)
        {
            return .on
        }
        return .high
    }

    private static func thinkingLevelKey(for provider: ProviderID, model: String) -> String {
        "provider.\(provider.rawValue).model.\(model).thinkingLevel"
    }

}

private extension ProviderID {
    var defaultBaseURL: String {
        switch self {
        case .umans:
            "https://api.code.umans.ai"
        case .kimi:
            "https://api.moonshot.ai/v1"
        case .kimiCode:
            "https://api.kimi.com/coding/v1"
        case .openAICompatible:
            "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .umans:
            "umans-coder"
        case .kimiCode:
            "kimi-for-coding"
        case .kimi, .openAICompatible:
            ""
        }
    }

    var credentialID: String {
        switch self {
        case .umans:
            "umans-api-key"
        case .kimi:
            "kimi-api-key"
        case .kimiCode:
            "kimi-code-api-key"
        case .openAICompatible:
            "openai-compatible-primary"
        }
    }

    var baseURLKey: String {
        "provider.\(rawValue).baseURL"
    }

    var modelKey: String {
        "provider.\(rawValue).model"
    }
}
