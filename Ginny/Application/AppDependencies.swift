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
    let citationRepository: CitationRepository?
    let searchIndex: LocalSearchIndex?
    let contextRepository: ContextRepository?

    init(
        credentialStore: any CredentialStore,
        transport: any StreamingTransport,
        modelCatalog: any ModelCatalogProviding,
        conversationRepository: ConversationRepository,
        artefactRepository: ArtefactRepository,
        sourceRepository: SourceRepository,
        attachmentStore: any AttachmentStore,
        relationshipRepository: RelationshipRepository,
        citationRepository: CitationRepository? = nil,
        searchIndex: LocalSearchIndex? = nil,
        contextRepository: ContextRepository? = nil
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.modelCatalog = modelCatalog
        self.conversationRepository = conversationRepository
        self.artefactRepository = artefactRepository
        self.sourceRepository = sourceRepository
        self.attachmentStore = attachmentStore
        self.relationshipRepository = relationshipRepository
        self.citationRepository = citationRepository
        self.searchIndex = searchIndex
        self.contextRepository = contextRepository
    }

    static func makeLive() throws -> AppDependencies {
        let container = try GinnyPersistence.makeContainer()
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let attachmentURL = applicationSupport
            .appendingPathComponent("Ginny", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        let conversationRepository = ConversationRepository(container: container)
        let artefactRepository = ArtefactRepository(container: container)
        let sourceRepository = SourceRepository(container: container)
        let relationshipRepository = RelationshipRepository(container: container)
        let citationRepository = CitationRepository(container: container)
        let contextRepository = ContextRepository(container: container)
        let searchIndex = LocalSearchIndex()
        let conversations = (try? conversationRepository.fetch()) ?? []
        let artefacts = (try? artefactRepository.fetchArtefacts()) ?? []
        let sources = (try? sourceRepository.fetch()) ?? []
        let relatedRelationships = (try? relationshipRepository.fetch(predicate: .relatedTo)) ?? []
        let derivedRelationships = (try? relationshipRepository.fetch(predicate: .derivedFrom)) ?? []
        let revisionRelationships = (try? relationshipRepository.fetch(predicate: .revisionOf)) ?? []
        let referenceRelationships = (try? relationshipRepository.fetch(predicate: .references)) ?? []
        let supportRelationships = (try? relationshipRepository.fetch(predicate: .supportedBy)) ?? []
        let relationships = relatedRelationships
            + derivedRelationships
            + revisionRelationships
            + referenceRelationships
            + supportRelationships
        let citations = (try? citationRepository.fetch()) ?? []
        let contexts = (try? contextRepository.fetch()) ?? []
        let conversationDocuments = conversations.flatMap { conversation in
            SearchDocumentFactory.documents(for: conversation)
        }
        let artefactDocuments = artefacts.flatMap { artefact in
            SearchDocumentFactory.documents(for: artefact)
        }
        let sourceDocuments = sources.map { source in
            SearchDocumentFactory.document(for: source)
        }
        let citationDocuments = citations.map { citation in
            SearchDocumentFactory.document(for: citation)
        }
        let contextDocuments = contexts.map { context in
            SearchDocumentFactory.document(for: context)
        }
        let relationshipDocuments = relationships.map { relationship in
            SearchDocumentFactory.document(for: relationship)
        }
        let initialDocuments = conversationDocuments
            + artefactDocuments
            + sourceDocuments
            + citationDocuments
            + contextDocuments
            + relationshipDocuments
        var initialChanges = initialDocuments.map(SearchIndexChange.upsert)
        initialChanges.append(contentsOf: relationships.map(SearchIndexChange.upsertRelationship))
        Task {
            await searchIndex.enqueue(contentsOf: initialChanges)
            await searchIndex.flush()
        }

        return AppDependencies(
            credentialStore: KeychainCredentialStore(),
            transport: URLSessionStreamingTransport(),
            modelCatalog: URLSessionModelCatalog(),
            conversationRepository: conversationRepository,
            artefactRepository: artefactRepository,
            sourceRepository: sourceRepository,
            attachmentStore: try FileAttachmentStore(rootURL: attachmentURL),
            relationshipRepository: relationshipRepository,
            citationRepository: citationRepository,
            searchIndex: searchIndex,
            contextRepository: contextRepository
        )
    }

    func makeSourceImporter() -> SourceImporter {
        SourceImporter(
            attachmentStore: attachmentStore,
            repository: sourceRepository,
            searchIndex: searchIndex
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
        let workspaceSearch = searchIndex.map(SearchWorkspaceTool.init(index:))

        return ToolRegistry(tools: [
            CurrentTimeTool(),
            DiscoverSkillsTool(catalog: catalog),
            ReadSkillTool(catalog: catalog),
            SearchWebTool(service: webSearch)
        ] + (workspaceSearch.map { [$0] } ?? []) + artefactTools)
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
