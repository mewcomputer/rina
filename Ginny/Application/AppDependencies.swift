import Foundation

/// Application-lifetime dependencies are constructed at the composition root.
struct AppDependencies: Sendable {
    let credentialStore: any CredentialStore
    let transport: any StreamingTransport

    static let live = AppDependencies(
        credentialStore: KeychainCredentialStore(),
        transport: URLSessionStreamingTransport()
    )

    func makeProvider(for configuration: ProviderConfiguration) -> OpenAICompatibleAdapter {
        OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: credentialStore,
            transport: transport
        )
    }
}
