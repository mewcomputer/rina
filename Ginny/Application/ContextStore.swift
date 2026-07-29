import Combine
import Foundation

@MainActor
final class ContextStore: ObservableObject {
    @Published private(set) var contexts: [Context]
    @Published private(set) var sources: [Source]
    @Published private(set) var persistenceError: String?

    private let contextRepository: ContextRepository?
    private let sourceRepository: SourceRepository
    private let searchIndex: LocalSearchIndex?

    init(
        contextRepository: ContextRepository?,
        sourceRepository: SourceRepository,
        searchIndex: LocalSearchIndex? = nil
    ) {
        self.contextRepository = contextRepository
        self.sourceRepository = sourceRepository
        self.searchIndex = searchIndex
        contexts = []
        sources = []
        persistenceError = nil
        refresh()
    }

    func refresh() {
        do {
            contexts = try contextRepository?.fetch() ?? []
            sources = try sourceRepository.fetch()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func save(_ context: Context) {
        guard let contextRepository else {
            persistenceError = "Contexts are unavailable in this workspace."
            return
        }

        do {
            try contextRepository.upsert(context)
            refresh()
            if let searchIndex {
                Task {
                    await searchIndex.enqueue(.upsert(SearchDocumentFactory.document(for: context)))
                    await searchIndex.flush()
                }
            }
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func remove(_ context: Context) {
        guard let contextRepository else {
            persistenceError = "Contexts are unavailable in this workspace."
            return
        }

        do {
            try contextRepository.delete(context)
            refresh()
            if let searchIndex {
                Task {
                    await searchIndex.enqueue(.remove(.context(context.id)))
                    await searchIndex.flush()
                }
            }
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func assemblyInput(
        for context: Context,
        messages: [Message],
        artefacts: [Artefact]
    ) -> ContextAssemblyInput {
        ContextMaterialResolver.input(
            for: context,
            messages: messages,
            artefacts: artefacts,
            sources: sources
        )
    }
}
