import Foundation

/// Application-lifetime dependencies are constructed at the composition root.
@MainActor
struct AppDependencies: Sendable {
    let credentialStore: any CredentialStore
    let transport: any StreamingTransport
    let modelCatalog: any ModelCatalogProviding
    let conversationRepository: ConversationRepository
    let artefactRepository: ArtefactRepository

    static let live = AppDependencies(
        credentialStore: KeychainCredentialStore(),
        transport: URLSessionStreamingTransport(),
        modelCatalog: URLSessionModelCatalog(),
        conversationRepository: try! ConversationRepository(),
        artefactRepository: try! ArtefactRepository()
    )

    func makeSkillCatalog() -> SkillCatalog {
        let persistedSkills = (try? artefactRepository.fetchSkills()) ?? []
        var skillsByID = Dictionary(uniqueKeysWithValues: CuratedSkills.all.map { ($0.id, $0) })
        for skill in persistedSkills {
            skillsByID[skill.id] = skill
        }
        return SkillCatalog(skills: Array(skillsByID.values))
    }

    func makeToolRegistry() -> ToolRegistry {
        let catalog = makeSkillCatalog()

        return ToolRegistry(tools: [
            CurrentTimeTool(),
            DiscoverSkillsTool(catalog: catalog),
            ReadSkillTool(catalog: catalog)
        ])
    }

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
