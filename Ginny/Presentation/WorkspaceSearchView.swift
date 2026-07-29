import SwiftUI

struct WorkspaceSearchView: View {
    let index: LocalSearchIndex?
    let conversations: [Conversation]
    let artefacts: [Artefact]
    let sources: [Source]
    let contexts: [Context]
    let titleForConversation: (Conversation) -> String
    let relationshipRepository: RelationshipRepository
    let openConversation: (Conversation) -> Void
    let openWorkspace: () -> Void
    let selectContext: (ContextID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var relationships: [RelationshipEdge] = []

    var body: some View {
        NavigationStack {
            Group {
                if index == nil {
                    ContentUnavailableView(
                        "Search unavailable",
                        systemImage: "magnifyingglass",
                        description: Text("Local workspace search is not available in this session.")
                    )
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search your workspace",
                        systemImage: "magnifyingglass",
                        description: Text("Find conversations, artefacts, sources, contexts, and citations.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results, id: \.nodeID) { result in
                        Button {
                            open(result)
                        } label: {
                            SearchResultRow(
                                result: result,
                                relationships: relationships(for: result.nodeID),
                                nameForNode: name(for:)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: query) {
            guard let index else {
                results = []
                return
            }
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            results = await index.search(query: trimmedQuery, limit: 50)
        }
        .task {
            var loaded: [RelationshipEdge] = []
            for predicate in RelationshipPredicate.allCases {
                loaded.append(contentsOf: (try? relationshipRepository.fetch(predicate: predicate)) ?? [])
            }
            relationships = loaded
        }
    }

    private func relationships(for nodeID: GraphNodeID) -> [RelationshipEdge] {
        relationships.filter { $0.source == nodeID || $0.target == nodeID }
    }

    private func open(_ result: SearchResult) {
        switch result.nodeID {
        case .conversation(let id):
            if let conversation = conversations.first(where: { $0.id == id }) {
                openConversation(conversation)
                dismiss()
            }
        case .message(let id):
            if let conversation = conversations.first(where: {
                $0.messages.contains(where: { $0.id == id })
            }) {
                openConversation(conversation)
                dismiss()
            }
        case .context(let id):
            selectContext(id)
            dismiss()
        case .artefact, .artefactRevision, .source, .citation, .relationship, .contentBlock, .skill:
            openWorkspace()
            dismiss()
        }
    }

    private func name(for nodeID: GraphNodeID) -> String {
        switch nodeID {
        case .conversation(let id):
            guard let conversation = conversations.first(where: { $0.id == id }) else {
                return "Conversation"
            }
            return titleForConversation(conversation)
        case .message:
            return "Message"
        case .artefact(let id):
            return artefacts.first(where: { $0.id == id })?.title ?? "Artefact"
        case .artefactRevision(let artefactID, _):
            return artefacts.first(where: { $0.id == artefactID })?.title ?? "Artefact revision"
        case .source(let id):
            return sources.first(where: { $0.id == id })?.displayName ?? "Source"
        case .context(let id):
            return contexts.first(where: { $0.id == id })?.name ?? "Context"
        case .citation:
            return "Citation"
        case .relationship:
            return "Relationship"
        case .contentBlock:
            return "Content"
        case .skill(let name):
            return name
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let relationships: [RelationshipEdge]
    let nameForNode: (GraphNodeID) -> String
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: result.kind.systemImage)
                    .foregroundStyle(theme.color("primary"))
                Text(result.title ?? result.kind.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.color("text.body"))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Text(result.kind.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.color("text.muted"))

            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.subheadline)
                    .foregroundStyle(theme.color("text.muted"))
                    .lineLimit(3)
            }

            if !relationships.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(relationships.prefix(3)) { edge in
                        Label {
                            Text("\(edge.predicate.rawValue) \(nameForNode(otherNode(for: edge)))")
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "arrow.turn.down.right")
                        }
                        .font(.caption)
                        .foregroundStyle(theme.color("text.muted"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func otherNode(for edge: RelationshipEdge) -> GraphNodeID {
        edge.source == result.nodeID ? edge.target : edge.source
    }
}

private extension SearchDocumentKind {
    var displayName: String {
        switch self {
        case .conversation: "Conversation"
        case .message: "Message"
        case .artefact: "Artefact"
        case .artefactRevision: "Artefact revision"
        case .source: "Source"
        case .citation: "Citation"
        case .context: "Context"
        case .relationship: "Relationship"
        }
    }

    var systemImage: String {
        switch self {
        case .conversation, .message: "bubble.left.and.bubble.right"
        case .artefact, .artefactRevision: "square.stack.3d.up"
        case .source: "doc.text"
        case .citation: "link"
        case .context: "rectangle.stack"
        case .relationship: "arrow.triangle.branch"
        }
    }
}
