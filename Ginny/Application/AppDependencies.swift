import Foundation

/// Application-lifetime dependencies are constructed at the composition root.
@MainActor
struct AppDependencies: Sendable {
    let credentialStore: any CredentialStore
    let transport: any StreamingTransport
    let modelCatalog: any ModelCatalogProviding
    let conversationRepository: ConversationRepository

    static let live = AppDependencies(
        credentialStore: KeychainCredentialStore(),
        transport: URLSessionStreamingTransport(),
        modelCatalog: URLSessionModelCatalog(),
        conversationRepository: try! ConversationRepository()
    )

    func makeProvider(for configuration: ProviderConfiguration) -> any ProviderAdapter {
        switch configuration.provider {
        case .umans:
            AnthropicMessagesAdapter(
                configuration: configuration,
                credentialStore: credentialStore,
                transport: transport
            )
        case .kimi, .kimiCode, .openAICompatible:
            OpenAICompatibleAdapter(
                configuration: configuration,
                credentialStore: credentialStore,
                transport: transport
            )
        }
    }
}
