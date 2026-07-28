import Combine
import Foundation

@MainActor
final class ProviderSettings: ObservableObject {
    static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"
    static let credentialID = "openai-compatible-primary"

    @Published var endpointText: String
    @Published var modelText: String
    @Published var credentialText: String
    @Published private(set) var validationMessage: String?

    private let defaults: UserDefaults
    private let credentialStore: any CredentialStore

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any CredentialStore = KeychainCredentialStore()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        endpointText = defaults.string(forKey: "provider.endpoint") ?? Self.defaultEndpoint
        modelText = defaults.string(forKey: "provider.model") ?? ""
        credentialText = (try? credentialStore.credential(for: Self.credentialID)) ?? ""
    }

    var configuration: ProviderConfiguration? {
        guard let endpoint = URL(string: endpointText.trimmingCharacters(in: .whitespacesAndNewlines)),
              endpoint.scheme == "https"
                || (endpoint.scheme == "http" && ["localhost", "127.0.0.1"].contains(endpoint.host ?? "")),
              !modelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return ProviderConfiguration(
            endpoint: endpoint,
            model: modelText.trimmingCharacters(in: .whitespacesAndNewlines),
            credentialID: Self.credentialID
        )
    }

    @discardableResult
    func save() -> Bool {
        let endpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint) else {
            validationMessage = "Enter a valid provider endpoint."
            return false
        }
        guard url.scheme == "https"
                || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? ""))
        else {
            validationMessage = "Use HTTPS, or a localhost endpoint for local development."
            return false
        }
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
            try credentialStore.save(credential, for: Self.credentialID)
        } catch {
            validationMessage = "The credential could not be saved securely."
            return false
        }

        defaults.set(endpoint, forKey: "provider.endpoint")
        defaults.set(model, forKey: "provider.model")
        endpointText = endpoint
        modelText = model
        credentialText = credential
        validationMessage = nil
        return true
    }
}
