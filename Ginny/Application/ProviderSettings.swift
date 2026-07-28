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
        let selectedProvider = ProviderID(rawValue: defaults.string(forKey: "provider.id") ?? "") ?? .umans
        provider = selectedProvider
        endpointText = defaults.string(forKey: selectedProvider.baseURLKey)
            ?? defaults.string(forKey: "provider.endpoint")
            ?? selectedProvider.defaultBaseURL
        modelText = defaults.string(forKey: selectedProvider.modelKey)
            ?? defaults.string(forKey: "provider.model")
            ?? selectedProvider.defaultModel
        credentialText = (try? credentialStore.credential(for: selectedProvider.credentialID)) ?? ""
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
            credentialID: provider.credentialID
        )
    }

    var validBaseURL: URL? {
        let endpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint),
              url.scheme == "https"
                || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? ""))
        else {
            return nil
        }
        return url
    }

    func selectProvider(_ provider: ProviderID) {
        self.provider = provider
        endpointText = defaults.string(forKey: provider.baseURLKey) ?? provider.defaultBaseURL
        modelText = defaults.string(forKey: provider.modelKey) ?? provider.defaultModel
        credentialText = (try? credentialStore.credential(for: provider.credentialID)) ?? ""
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
                modelText = availableModels.first(where: { $0.id == "umans-coder" })?.id
                    ?? availableModels.first?.id
                    ?? modelText
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

    @discardableResult
    func save() -> Bool {
        guard validBaseURL != nil else {
            validationMessage = "Use HTTPS, or a localhost endpoint for local development."
            return false
        }
        let endpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
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

}

private extension ProviderID {
    var defaultBaseURL: String {
        switch self {
        case .umans:
            "https://api.code.umans.ai"
        case .kimi:
            "https://api.moonshot.ai/v1"
        case .openAICompatible:
            "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .umans:
            "umans-coder"
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
