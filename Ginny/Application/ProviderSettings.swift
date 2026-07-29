import Combine
import Foundation

@MainActor
final class ProviderSettings: ObservableObject {
    static let defaultEndpoint = "https://api.code.umans.ai"
    static let credentialID = "umans-api-key"
    private static let legacyCredentialID = "openai-compatible-primary"

    @Published var provider: ProviderID
    @Published var endpointText: String
    @Published var modelText: String
    @Published var credentialText: String
    @Published var webSearchProvider: WebSearchProviderID
    @Published var webSearchEndpointText: String
    @Published var webSearchCredentialText: String
    @Published var thinkingLevel: ThinkingLevel = .high
    @Published var allowAllArtefactWebRequests: Bool
    @Published var autoApproveArtefactWrites: Bool
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
        allowAllArtefactWebRequests = defaults.bool(forKey: ArtefactPreferences.allowAllNetworkRequestsKey)
        autoApproveArtefactWrites = defaults.bool(forKey: ArtefactPreferences.autoApproveWritesKey)
        let storedProvider = defaults.string(forKey: "provider.id")
        let legacyEndpoint = defaults.string(forKey: "provider.endpoint")
        let selectedProvider = ProviderID(rawValue: storedProvider ?? "")
            ?? Self.legacyProvider(for: legacyEndpoint)
            ?? .umans
        provider = selectedProvider
        let storedBaseURL = defaults.string(forKey: selectedProvider.baseURLKey)
            ?? (storedProvider == nil ? nil : defaults.string(forKey: "provider.endpoint"))
        let storedModel = defaults.string(forKey: selectedProvider.modelKey)
            ?? defaults.string(forKey: "provider.model")
        endpointText = Self.normalizedBaseURLText(storedBaseURL, provider: selectedProvider)
            ?? selectedProvider.defaultBaseURL
        modelText = storedModel ?? selectedProvider.defaultModel
        credentialText = (try? credentialStore.credential(for: selectedProvider.credentialID))
            ?? (storedProvider == nil
                ? (try? credentialStore.credential(for: Self.legacyCredentialID))
                : nil)
            ?? ""
        let selectedWebSearchProvider = WebSearchProviderID(
            rawValue: defaults.string(forKey: WebSearchPreferences.providerKey) ?? ""
        ) ?? .tavily
        webSearchProvider = selectedWebSearchProvider
        webSearchEndpointText = defaults.string(
            forKey: WebSearchPreferences.baseURLKeyPrefix + selectedWebSearchProvider.rawValue
        ) ?? selectedWebSearchProvider.defaultBaseURL
        webSearchCredentialText = (try? credentialStore.credential(
            for: selectedWebSearchProvider.credentialID
        )) ?? ""
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
            thinkingLevel: thinkingOptions.contains(thinkingLevel) ? thinkingLevel : nil,
            supportsTools: selectedModel?.capabilities.supportsTools
        )
    }

    var thinkingOptions: [ThinkingLevel] {
        if let reasoning = selectedModel?.capabilities.reasoning,
           reasoning.supported == true
        {
            var options = reasoning.levels.compactMap {
                ThinkingLevel(rawValue: $0.lowercased())
            }
            if reasoning.canDisable == true, !options.contains(.off) {
                options.insert(.off, at: 0)
            }
            return options.isEmpty
                ? (reasoning.canDisable == true ? [.off, .on] : [.on])
                : options
        }

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

    func selectWebSearchProvider(_ provider: WebSearchProviderID) {
        webSearchProvider = provider
        webSearchEndpointText = defaults.string(
            forKey: WebSearchPreferences.baseURLKeyPrefix + provider.rawValue
        ) ?? provider.defaultBaseURL
        webSearchCredentialText = (try? credentialStore.credential(for: provider.credentialID)) ?? ""
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
            synchronizeThinkingLevel()
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
        synchronizeThinkingLevel()
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
        if !availableModels.isEmpty,
           !availableModels.contains(where: { $0.id == model })
        {
            validationMessage = "Choose a model from the provider catalog."
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
        persistArtefactPreferences()
        persistWebSearchPreferences()
        endpointText = endpoint
        modelText = model
        credentialText = credential
        validationMessage = nil
        return true
    }

    func persistArtefactPreferences() {
        defaults.set(allowAllArtefactWebRequests, forKey: ArtefactPreferences.allowAllNetworkRequestsKey)
        defaults.set(autoApproveArtefactWrites, forKey: ArtefactPreferences.autoApproveWritesKey)
    }

    func persistWebSearchPreferences() {
        let endpoint = webSearchEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil else {
            return
        }

        defaults.set(webSearchProvider.rawValue, forKey: WebSearchPreferences.providerKey)
        defaults.set(
            url.absoluteString,
            forKey: WebSearchPreferences.baseURLKeyPrefix + webSearchProvider.rawValue
        )
        let credential = webSearchCredentialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !credential.isEmpty {
            try? credentialStore.save(credential, for: webSearchProvider.credentialID)
        }
        webSearchEndpointText = url.absoluteString
        webSearchCredentialText = credential
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

    private static func legacyProvider(for endpoint: String?) -> ProviderID? {
        guard let endpoint, let url = URL(string: endpoint), let host = url.host else {
            return nil
        }
        switch host {
        case "api.code.umans.ai":
            return .umans
        case "api.moonshot.ai":
            return .kimi
        case "api.kimi.com":
            return .kimiCode
        default:
            return .openAICompatible
        }
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

    private var selectedModel: ProviderModel? {
        availableModels.first { $0.id == modelText }
    }

    private func synchronizeThinkingLevel() {
        let fallback: ThinkingLevel
        if let reasoning = selectedModel?.capabilities.reasoning,
           reasoning.supported == true
        {
            fallback = reasoning.defaultLevel
                .flatMap { ThinkingLevel(rawValue: $0.lowercased()) }
                ?? thinkingOptions.first
                ?? .on
        } else {
            fallback = Self.defaultThinkingLevel(for: provider, model: modelText)
        }

        thinkingLevel = Self.storedThinkingLevel(
            defaults: defaults,
            provider: provider,
            model: modelText,
            fallback: fallback
        )
        guard let firstOption = thinkingOptions.first,
              !thinkingOptions.contains(thinkingLevel)
        else {
            return
        }
        thinkingLevel = firstOption
    }

    private static func storedThinkingLevel(
        defaults: UserDefaults,
        provider: ProviderID,
        model: String,
        fallback: ThinkingLevel = .high
    ) -> ThinkingLevel {
        guard let rawValue = defaults.string(forKey: thinkingLevelKey(for: provider, model: model)),
              let level = ThinkingLevel(rawValue: rawValue)
        else {
            return fallback
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
