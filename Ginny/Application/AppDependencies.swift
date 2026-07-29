import Foundation

/// Application-lifetime dependencies are constructed at the composition root.
@MainActor
struct AppDependencies: Sendable {
    let credentialStore: any CredentialStore
    let transport: any StreamingTransport
    let modelCatalog: any ModelCatalogProviding
    let conversationRepository: ConversationRepository
    let artefactRepository: ArtefactRepository
    let sourceRepository: SourceRepository
    let attachmentStore: any AttachmentStore
    let relationshipRepository: RelationshipRepository

    static func makeLive() throws -> AppDependencies {
        let container = try GinnyPersistence.makeContainer()
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let attachmentURL = applicationSupport
            .appendingPathComponent("Ginny", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        return AppDependencies(
            credentialStore: KeychainCredentialStore(),
            transport: URLSessionStreamingTransport(),
            modelCatalog: URLSessionModelCatalog(),
            conversationRepository: ConversationRepository(container: container),
            artefactRepository: ArtefactRepository(container: container),
            sourceRepository: SourceRepository(container: container),
            attachmentStore: try FileAttachmentStore(rootURL: attachmentURL),
            relationshipRepository: RelationshipRepository(container: container)
        )
    }

    func makeSourceImporter() -> SourceImporter {
        SourceImporter(
            attachmentStore: attachmentStore,
            repository: sourceRepository
        )
    }

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
        let artefactTools = ArtefactToolSet(repository: artefactRepository).tools
        let webSearch = WebSearchService(credentialStore: credentialStore)

        return ToolRegistry(tools: [
            CurrentTimeTool(),
            DiscoverSkillsTool(catalog: catalog),
            ReadSkillTool(catalog: catalog),
            SearchWebTool(service: webSearch)
        ] + artefactTools)
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
