import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

private extension SourceExtractionState {
    var displayName: String {
        switch self {
        case .pending: "Pending extraction"
        case .extracting: "Extracting"
        case .ready: "Ready"
        case .partiallyReady: "Partially extracted"
        case .failed: "Extraction failed"
        }
    }
}

private extension ArtefactKind {
    var displayName: String {
        switch self {
        case .document: "Document"
        case .code: "Code"
        case .web: "Web"
        case .inlineWeb: "Inline web"
        }
    }

    var systemImage: String {
        switch self {
        case .document: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .web: "globe"
        case .inlineWeb: "rectangle.on.rectangle"
        }
    }
}

@MainActor
struct WorkspaceLibraryView: View {
    @ObservedObject var store: ArtefactStore
    let sourceImporter: SourceImporter
    let relationshipRepository: RelationshipRepository
    let sharingService: AtprotoSharingService
    @ObservedObject var publicationStore: AtprotoPublicationStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var section: WorkspaceSection = .artefacts
    @State private var selectedArtefact: Artefact?
    @State private var selectedSkill: Skill?
    @State private var artefactToShare: Artefact?
    @State private var sources: [Source] = []
    @State private var sharedFile: ExportedFile?
    @State private var isImportingSource = false
    @State private var importMessage: String?
    @State private var relationships: [RelationshipEdge] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Workspace", selection: $section) {
                    ForEach(WorkspaceSection.allCases, id: \.self) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                List {
                    if section == .artefacts {
                        artefactRows
                    } else if section == .sources {
                        sourceRows
                    } else {
                        skillRows
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New artefact", systemImage: "square.and.pencil") {
                            createArtefact()
                        }
                        Button("New skill", systemImage: "wand.and.stars") {
                            createSkill()
                        }
                        Divider()
                        Button("Import source", systemImage: "square.and.arrow.down") {
                            isImportingSource = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Workspace actions")
                }
            }
        }
        .sheet(item: $selectedArtefact) { artefact in
            ArtefactEditorView(artefact: artefact) { updated in
                store.save(updated)
            }
        }
        .sheet(item: $selectedSkill) { skill in
            SkillEditorView(skill: skill) { updated in
                store.save(updated)
            }
        }
        .sheet(item: $artefactToShare) { artefact in
            ArtefactSharePreviewSheet(
                artefact: artefact,
                publication: publicationStore.publications.first {
                    $0.collection == AtprotoRecordCollection.artefact
                        && $0.subjectID == artefact.id.rawValue.rawValue
                },
                sharingService: sharingService,
                publicationStore: publicationStore
            )
            .environment(\.ginnyTheme, theme)
            .preferredColorScheme(theme.mode.colorScheme)
        }
        .fileImporter(
            isPresented: $isImportingSource,
            allowedContentTypes: SourceImporter.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            importSource(from: url)
        }
        .alert(
            "Source import",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("Done") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .sheet(item: $sharedFile) { file in
            FileShareSheet(file: file)
                .presentationDetents([.medium])
        }
        .tint(theme.color("primary"))
        .task {
            reloadSources()
            reloadRelationships()
        }
    }

    @ViewBuilder
    private var artefactRows: some View {
        if store.artefacts.isEmpty {
            ContentUnavailableView(
                "No artefacts yet",
                systemImage: "square.and.pencil",
                description: Text("Save an answer to make durable work.")
            )
            .listRowSeparator(.hidden)
        } else {
            ForEach(store.artefacts) { artefact in
                Button {
                    selectedArtefact = artefact
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artefact.title)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(artefact.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            relationshipLabels(for: artefact)
                        }
                    } icon: {
                        Image(systemName: artefact.kind.systemImage)
                            .foregroundStyle(theme.color("primary"))
                    }
                }
                .contextMenu {
                    Button("Share", systemImage: "square.and.arrow.up") {
                        artefactToShare = artefact
                    }
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        ForEach(ArtefactExportFormat.allCases, id: \.self) { format in
                            Button(format.fileExtension.uppercased()) {
                                export(artefact, as: format)
                            }
                        }
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    store.remove(store.artefacts[offset])
                }
            }
        }
    }

    @ViewBuilder
    private var sourceRows: some View {
        if sources.isEmpty {
            ContentUnavailableView(
                "No sources yet",
                systemImage: "doc.on.doc",
                description: Text("Import a document to make it available to Ginny.")
            )
            .listRowSeparator(.hidden)
        } else {
            ForEach(sources) { source in
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.displayName)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(source.extractionState.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        relationshipLabels(for: .source(source.id))
                    }
                } icon: {
                    Image(systemName: "doc.text")
                        .foregroundStyle(theme.color("primary"))
                }
                .contextMenu {
                    Button("Export", systemImage: "square.and.arrow.up") {
                        export(source)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var skillRows: some View {
        if store.availableSkills.isEmpty {
            ContentUnavailableView(
                "No skills yet",
                systemImage: "wand.and.stars",
                description: Text("Create a reusable instruction set for your work.")
            )
            .listRowSeparator(.hidden)
        } else {
            ForEach(store.availableSkills) { skill in
                Button {
                    selectedSkill = skill
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: skill.isBuiltIn ? "wand.and.stars" : "person.crop.circle")
                            .foregroundStyle(theme.color("primary"))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(skill.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    let skill = store.availableSkills[offset]
                    guard !skill.isBuiltIn else { continue }
                    store.remove(skill)
                }
            }
        }
    }

    private func createArtefact() {
        let artefact = Artefact(title: "Untitled artefact", kind: .document)
        store.save(artefact)
        selectedArtefact = artefact
    }

    private func createSkill() {
        guard let skill = store.createSkill(
            name: "New skill",
            summary: "A reusable instruction set.",
            instructions: "Describe how this skill should guide the model.",
            targetKinds: [.document, .code, .web, .inlineWeb]
        ) else { return }
        selectedSkill = skill
    }

    private func importSource(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let source = try await sourceImporter.importFile(at: url)
                reloadSources()
                importMessage = "Imported \(source.displayName)."
            } catch let error as SourceImportError {
                importMessage = error.localizedDescription
            } catch {
                importMessage = "Ginny couldn’t import that source."
            }
        }
    }

    private func export(_ artefact: Artefact, as format: ArtefactExportFormat) {
        do {
            sharedFile = try ArtefactExporter().export(artefact, as: format)
        } catch {
            importMessage = "Ginny couldn’t export that artefact."
        }
    }

    private func export(_ source: Source) {
        Task { @MainActor in
            do {
                sharedFile = try await SourceExporter(
                    attachmentStore: sourceImporter.attachmentStore
                ).export(source)
            } catch {
                importMessage = "Ginny couldn’t export that source."
            }
        }
    }

    private func reloadSources() {
        sources = (try? sourceImporter.repository.fetch()) ?? []
    }

    private func reloadRelationships() {
        relationships = RelationshipPredicate.allCases.flatMap { predicate in
            (try? relationshipRepository.fetch(predicate: predicate)) ?? []
        }
    }

    @ViewBuilder
    private func relationshipLabels(for artefact: Artefact) -> some View {
        relationshipLabels(for: Set([
            .artefact(artefact.id)
        ] + artefact.revisions.map { revision in
            .artefactRevision(artefactID: artefact.id, revisionID: revision.id)
        }))
    }

    @ViewBuilder
    private func relationshipLabels(for node: GraphNodeID) -> some View {
        relationshipLabels(for: Set([node]))
    }

    @ViewBuilder
    private func relationshipLabels(for nodes: Set<GraphNodeID>) -> some View {
        ForEach(Array(relationships(for: nodes).prefix(2))) { edge in
            Text("\(edge.predicate.rawValue) \(name(for: otherNode(of: edge, in: nodes)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func relationships(for nodes: Set<GraphNodeID>) -> [RelationshipEdge] {
        relationships.filter { edge in
            nodes.contains(edge.source) || nodes.contains(edge.target)
        }
    }

    private func otherNode(of edge: RelationshipEdge, in nodes: Set<GraphNodeID>) -> GraphNodeID {
        nodes.contains(edge.source) ? edge.target : edge.source
    }

    private func name(for node: GraphNodeID) -> String {
        switch node {
        case .artefact(let id):
            return store.artefacts.first(where: { $0.id == id })?.title ?? "Artefact"
        case .artefactRevision(let artefactID, _):
            return store.artefacts.first(where: { $0.id == artefactID })?.title ?? "Artefact revision"
        case .source(let id):
            return sources.first(where: { $0.id == id })?.displayName ?? "Source"
        case .conversation, .message, .contentBlock, .citation, .context, .relationship, .skill:
            return "Workspace item"
        }
    }
}

@MainActor
private struct FileShareSheet: UIViewControllerRepresentable {
    let file: ExportedFile
    typealias UIViewControllerType = UIActivityViewController

    func makeUIViewController(
        context: UIViewControllerRepresentableContext<FileShareSheet>
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [SharedFileActivityItem(file: file)],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: UIViewControllerRepresentableContext<FileShareSheet>
    ) {}
}

private final class SharedFileActivityItem: NSObject, UIActivityItemSource {
    let file: ExportedFile

    init(file: ExportedFile) {
        self.file = file
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        file.data
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        file.data
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        file.filename
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        file.contentTypeIdentifier
    }
}

private enum WorkspaceSection: CaseIterable {
    case artefacts
    case sources
    case skills

    var title: String {
        switch self {
        case .artefacts: "Artefacts"
        case .sources: "Sources"
        case .skills: "Skills"
        }
    }
}

@MainActor
private struct ArtefactEditorView: View {
    let initialArtefact: Artefact
    let onSave: (Artefact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var source: String
    @State private var mode: ArtefactEditorMode
    @State private var networkOriginsText: String
    @AppStorage(ArtefactPreferences.allowAllNetworkRequestsKey) private var allowAllNetworkRequests = false

    init(artefact: Artefact, onSave: @escaping (Artefact) -> Void) {
        self.initialArtefact = artefact
        self.onSave = onSave
        _title = State(initialValue: artefact.title)
        _source = State(initialValue: artefact.currentRevision?.source ?? "")
        _mode = State(initialValue: artefact.kind == .web || artefact.kind == .inlineWeb ? .preview : .source)
        _networkOriginsText = State(
            initialValue: ArtefactNetworkPolicy(
                metadata: artefact.currentRevision?.metadata ?? artefact.metadata
            ).origins.joined(separator: "\n")
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Title", text: $title)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                if isWebArtefact {
                    Picker("Editor mode", selection: $mode) {
                        ForEach(ArtefactEditorMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    networkAccessEditor
                }

                editorContent
            }
            .navigationTitle(initialArtefact.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isWebArtefact && !networkPolicy.isValid)
                }
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if isWebArtefact, mode == .preview {
            WebArtefactPreview(
                html: source,
                isInline: initialArtefact.kind == .inlineWeb,
                networkOrigins: networkPolicy.origins,
                allowAllNetworkRequests: allowAllNetworkRequests
            )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(16)
        } else {
            TextEditor(text: $source)
                .font(initialArtefact.kind == .document ? .body : .system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }

    private var isWebArtefact: Bool {
        initialArtefact.kind == .web || initialArtefact.kind == .inlineWeb
    }

    private var networkPolicy: ArtefactNetworkPolicy {
        ArtefactNetworkPolicy(
            origins: networkOriginsText
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }

    private var networkAccessEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Network access")
                .font(.subheadline.weight(.semibold))

            TextField(
                "https://api.example.com",
                text: $networkOriginsText,
                axis: .vertical
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.caption.monospaced())
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("one exact HTTPS origin per line. leave empty to keep network access off.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !networkPolicy.isValid {
                Text("use HTTPS origins only, without paths, credentials, or local addresses.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func save() {
        var artefact = initialArtefact
        artefact.setTitle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled artefact" : title)
        var metadata = initialArtefact.currentRevision?.metadata ?? initialArtefact.metadata
        metadata.removeValue(forKey: ArtefactNetworkPolicy.metadataKey)
        if let networkOrigins = ArtefactNetworkPolicy.metadataValue(for: networkPolicy.origins) {
            metadata[ArtefactNetworkPolicy.metadataKey] = networkOrigins
        }
        metadata["edited"] = "true"
        _ = artefact.checkpoint(
            source: source,
            renderedContent: isWebArtefact ? source : nil,
            metadata: metadata
        )
        onSave(artefact)
        dismiss()
    }
}

@MainActor
private struct ArtefactSharePreviewSheet: View {
    let artefact: Artefact
    let publication: AtprotoPublication?
    let sharingService: AtprotoSharingService
    @ObservedObject var publicationStore: AtprotoPublicationStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var publishedPublication: AtprotoPublication?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(publication == nil ? "Share artefact" : "Update public snapshot")
                        .font(.title2.weight(.semibold))
                    Text(artefact.title)
                        .font(.headline)
                    Text("The current saved revision becomes a public atproto record. Local revision history stays on this device.")
                        .font(.subheadline)
                        .foregroundStyle(theme.color("text.muted"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Public snapshot", systemImage: "globe")
                        .font(.headline)
                    Text("Source, rendered content, and artefact metadata are included in this public snapshot.")
                        .font(.footnote)
                        .foregroundStyle(theme.color("text.muted"))
                }
                .padding(16)
                .background(theme.color("card"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer()

                Button(action: publish) {
                    HStack {
                        if isWorking { ProgressView().tint(theme.color("primary_foreground")) }
                        Text(publication == nil ? "Publish publicly" : "Update public snapshot")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || artefact.currentRevision == nil)

                if let publicURL = publishedPublication?.publicWebURL ?? publication?.publicWebURL {
                    Button("Open public page", systemImage: "arrow.up.right") {
                        openURL(publicURL)
                    }
                    .frame(maxWidth: .infinity)
                }

                if publishedPublication != nil || publication != nil {
                    Button("Stop sharing", role: .destructive, action: stopSharing)
                        .frame(maxWidth: .infinity)
                        .disabled(isWorking)
                }
            }
            .padding(20)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Couldn’t share artefact",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("Done") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func publish() {
        isWorking = true
        Task {
            do {
                let snapshot = try AtprotoSnapshotBuilder.artefact(artefact)
                let published = try await sharingService.publish(
                    snapshot,
                    publication: publication,
                    subjectID: artefact.id.rawValue.rawValue
                )
                publicationStore.save(published)
                publishedPublication = published
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func stopSharing() {
        guard let publication = publishedPublication ?? publication else { return }
        isWorking = true
        Task {
            do {
                try await sharingService.delete(publication)
                publicationStore.remove(collection: publication.collection, rkey: publication.rkey)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

private enum ArtefactEditorMode: CaseIterable {
    case preview
    case source

    var title: String {
        switch self {
        case .preview: "Preview"
        case .source: "Source"
        }
    }
}

@MainActor
private struct SkillEditorView: View {
    let initialSkill: Skill
    let onSave: (Skill) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var summary: String
    @State private var instructions: String
    @State private var keywords: String
    @State private var isDiscoverable: Bool
    @State private var targetKinds: Set<ArtefactKind>

    init(skill: Skill, onSave: @escaping (Skill) -> Void) {
        self.initialSkill = skill
        self.onSave = onSave
        _name = State(initialValue: skill.name)
        _summary = State(initialValue: skill.summary)
        _instructions = State(initialValue: skill.currentRevision?.instructions ?? "")
        _keywords = State(initialValue: skill.keywords.joined(separator: ", "))
        _isDiscoverable = State(initialValue: skill.isDiscoverable)
        _targetKinds = State(initialValue: skill.targetKinds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Skill") {
                    TextField("Name", text: $name)
                    TextField("Summary", text: $summary, axis: .vertical)
                    Toggle("Available to discovery", isOn: $isDiscoverable)
                }

                Section("Instructions") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 180)
                        .font(.body)
                }

                Section("Applies to") {
                    ForEach(ArtefactKind.allCases, id: \.self) { kind in
                        Toggle(kind.displayName, isOn: binding(for: kind))
                    }
                }

                Section("Keywords") {
                    TextField("frontend, accessibility", text: $keywords)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Edit skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func binding(for kind: ArtefactKind) -> Binding<Bool> {
        Binding(
            get: { targetKinds.contains(kind) },
            set: { includes in
                if includes {
                    targetKinds.insert(kind)
                } else {
                    targetKinds.remove(kind)
                }
            }
        )
    }

    private func save() {
        var skill = initialSkill
        skill.updateMetadata(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled skill" : name,
            summary: summary,
            targetKinds: targetKinds,
            keywords: keywords
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            isDiscoverable: isDiscoverable
        )
        _ = skill.update(instructions: instructions)
        onSave(skill)
        dismiss()
    }
}

struct WebArtefactPreview: UIViewRepresentable {
    static let maxInlineHeight: CGFloat = 520

    let html: String
    let isInline: Bool
    let networkOrigins: [String]
    let allowAllNetworkRequests: Bool
    let onNetworkOriginRequest: ((String) -> Void)?
    @Binding private var contentHeight: CGFloat
    @Environment(\.ginnyTheme) private var theme

    init(
        html: String,
        isInline: Bool,
        networkOrigins: [String] = [],
        contentHeight: Binding<CGFloat> = .constant(220),
        allowAllNetworkRequests: Bool = false,
        onNetworkOriginRequest: ((String) -> Void)? = nil
    ) {
        self.html = html
        self.isInline = isInline
        self.networkOrigins = ArtefactNetworkPolicy(origins: networkOrigins).origins
        self.allowAllNetworkRequests = allowAllNetworkRequests
        self.onNetworkOriginRequest = onNetworkOriginRequest
        _contentHeight = contentHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: UIViewRepresentableContext<WebArtefactPreview>) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "ginnyNetworkPolicy")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = true
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(
        _ webView: WKWebView,
        context: UIViewRepresentableContext<WebArtefactPreview>
    ) {
        let contentHeight = $contentHeight
        context.coordinator.onContentHeightChange = { height in
            guard abs(contentHeight.wrappedValue - height) > 1 else { return }
            contentHeight.wrappedValue = height
        }
        context.coordinator.onNetworkOriginRequest = onNetworkOriginRequest
        context.coordinator.networkOrigins = networkOrigins
        context.coordinator.allowAllNetworkRequests = allowAllNetworkRequests
        let renderKey = "\(theme.id)|\(isInline)|\(networkOrigins)|\(allowAllNetworkRequests)|\(html)"
        guard context.coordinator.lastRenderKey != renderKey else { return }
        context.coordinator.lastRenderKey = renderKey
        webView.loadHTMLString(renderedDocument, baseURL: nil)
    }

    var renderedDocument: String {
        Self.document(
            for: html,
            isInline: isInline,
            networkOrigins: networkOrigins,
            cssVariables: theme.cssVariables,
            isDark: theme.mode == .dark,
            allowAllNetworkRequests: allowAllNetworkRequests
        )
    }

    static func document(
        for content: String,
        isInline: Bool,
        networkOrigins: [String] = [],
        cssVariables: [String: String] = GinnyThemeKeyDefaults.cssVariables,
        isDark: Bool = true,
        allowAllNetworkRequests: Bool = false
    ) -> String {
        let viewport = "width=device-width, initial-scale=1.0, viewport-fit=cover"
        let connectSource = allowAllNetworkRequests
            ? "https:"
            : ArtefactNetworkPolicy(origins: networkOrigins).cspConnectSource
        let head = """
        <meta name="viewport" content="\(viewport)">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline' https://cdn.jsdelivr.net; img-src data: blob:; font-src data:; connect-src \(connectSource); frame-src 'none';">
        <script>
        (() => {
            document.addEventListener("securitypolicyviolation", event => {
                if (event.effectiveDirective !== "connect-src") { return; }
                try {
                    const origin = new URL(event.blockedURI, window.location.href).origin;
                    window.webkit?.messageHandlers?.ginnyNetworkPolicy?.postMessage({ origin });
                } catch (_) {}
            });
        })();
        </script>
        <script src="\(tailwindBrowserURL)"></script>
        <style type="text/tailwindcss">\(styleSheet(cssVariables: cssVariables, isInline: isInline, isDark: isDark))</style>
        """

        guard content.range(of: "<html", options: .caseInsensitive) != nil else {
            return """
            <!doctype html>
            <html>
            <head>\(head)</head>
            <body>\(content)</body>
            </html>
            """
        }

        var document = content
        if let headStart = document.range(of: "<head", options: .caseInsensitive),
           let headEnd = document.range(
               of: ">",
               range: headStart.upperBound..<document.endIndex
           )
        {
            document.insert(contentsOf: head, at: headEnd.upperBound)
            return document
        }

        let headMarkup = "<head>\(head)</head>"
        if let bodyStart = document.range(of: "<body", options: .caseInsensitive) {
            document.insert(contentsOf: headMarkup, at: bodyStart.lowerBound)
            return document
        }

        if let htmlStart = document.range(of: "<html", options: .caseInsensitive),
           let htmlEnd = document.range(
               of: ">",
               range: htmlStart.upperBound..<document.endIndex
           )
        {
            document.insert(contentsOf: headMarkup, at: htmlEnd.upperBound)
            return document
        }

        return "<!doctype html><html>\(headMarkup)<body>\(document)</body></html>"
    }

    private static let tailwindBrowserURL =
        "https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.1.11"

    private static func styleSheet(
        cssVariables: [String: String],
        isInline: Bool,
        isDark: Bool
    ) -> String {
        let fallbackVariables = GinnyThemeKeyDefaults.cssVariables
        var variables = fallbackVariables
        variables.merge(cssVariables) { _, replacement in replacement }
        let rootVariables = variables.keys.sorted().map { key in
            "--\(key): \(variables[key]!);"
        }.joined(separator: "\n                    ")
        let bodyPadding = isInline ? "16px" : "20px"

        return """
            :root {
                \(rootVariables)
                --radius-sm: calc(var(--radius) - 4px);
                --radius-md: calc(var(--radius) - 2px);
                --radius-lg: var(--radius);
                --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.08);
                --shadow-md: 0 4px 12px 0 rgb(0 0 0 / 0.12);
            }
            @theme {
                --color-background: var(--background);
                --color-foreground: var(--foreground);
                --color-card: var(--card);
                --color-card-foreground: var(--card-foreground);
                --color-primary: var(--primary);
                --color-primary-foreground: var(--primary-foreground);
                --color-secondary: var(--secondary);
                --color-secondary-foreground: var(--secondary-foreground);
                --color-muted: var(--muted);
                --color-muted-foreground: var(--muted-foreground);
                --color-accent: var(--accent);
                --color-accent-foreground: var(--accent-foreground);
                --color-destructive: var(--destructive);
                --color-ring: var(--ring);
                --radius-sm: calc(var(--radius) - 4px);
                --radius-md: calc(var(--radius) - 2px);
                --radius-lg: var(--radius);
            }
            @layer base {
                *, ::before, ::after { box-sizing: border-box; }
                html, body { margin: 0; min-height: 100%; }
                body {
                    padding: \(bodyPadding);
                    color: var(--foreground);
                    background: var(--background);
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                    color-scheme: \(isDark ? "dark" : "light");
                }
                button, input, textarea, select {
                    font: inherit;
                    color: inherit;
                }
                button {
                    border: 1px solid var(--border);
                    border-radius: var(--radius-md);
                    background: var(--card);
                    padding: 0.65rem 0.9rem;
                }
                button:focus-visible, input:focus-visible, textarea:focus-visible, select:focus-visible {
                    outline: 2px solid var(--ring);
                    outline-offset: 2px;
                }
                a { color: var(--primary); }
                img, svg, video { max-width: 100%; height: auto; }
            }
            @layer utilities {
                .container { width: 100%; margin-inline: auto; max-width: 72rem; }
                .block { display: block; }
                .inline-block { display: inline-block; }
                .flex { display: flex; }
                .inline-flex { display: inline-flex; }
                .grid { display: grid; }
                .hidden { display: none; }
                .flex-col { flex-direction: column; }
                .flex-wrap { flex-wrap: wrap; }
                .items-start { align-items: flex-start; }
                .items-center { align-items: center; }
                .items-end { align-items: flex-end; }
                .justify-start { justify-content: flex-start; }
                .justify-center { justify-content: center; }
                .justify-between { justify-content: space-between; }
                .justify-end { justify-content: flex-end; }
                .gap-1 { gap: 0.25rem; }
                .gap-2 { gap: 0.5rem; }
                .gap-3 { gap: 0.75rem; }
                .gap-4 { gap: 1rem; }
                .gap-6 { gap: 1.5rem; }
                .w-full { width: 100%; }
                .h-full { height: 100%; }
                .max-w-sm { max-width: 24rem; }
                .max-w-md { max-width: 28rem; }
                .max-w-lg { max-width: 32rem; }
                .p-1 { padding: 0.25rem; }
                .p-2 { padding: 0.5rem; }
                .p-3 { padding: 0.75rem; }
                .p-4 { padding: 1rem; }
                .p-6 { padding: 1.5rem; }
                .px-2 { padding-inline: 0.5rem; }
                .px-3 { padding-inline: 0.75rem; }
                .px-4 { padding-inline: 1rem; }
                .py-1 { padding-block: 0.25rem; }
                .py-2 { padding-block: 0.5rem; }
                .py-3 { padding-block: 0.75rem; }
                .py-4 { padding-block: 1rem; }
                .rounded-sm { border-radius: var(--radius-sm); }
                .rounded-md { border-radius: var(--radius-md); }
                .rounded-lg { border-radius: var(--radius-lg); }
                .rounded-full { border-radius: 9999px; }
                .border { border: 1px solid var(--border); }
                .border-0 { border-width: 0; }
                .bg-background { background: var(--background); }
                .bg-card { background: var(--card); }
                .bg-primary { background: var(--primary); }
                .bg-secondary { background: var(--secondary); }
                .bg-muted { background: var(--muted); }
                .bg-accent { background: var(--accent); }
                .bg-destructive { background: var(--destructive); }
                .text-foreground { color: var(--foreground); }
                .text-card-foreground { color: var(--card-foreground); }
                .text-primary { color: var(--primary); }
                .text-primary-foreground { color: var(--primary-foreground); }
                .text-secondary-foreground { color: var(--secondary-foreground); }
                .text-muted-foreground { color: var(--muted-foreground); }
                .text-accent-foreground { color: var(--accent-foreground); }
                .text-destructive { color: var(--destructive); }
                .text-xs { font-size: 0.75rem; line-height: 1rem; }
                .text-sm { font-size: 0.875rem; line-height: 1.25rem; }
                .text-base { font-size: 1rem; line-height: 1.5rem; }
                .text-lg { font-size: 1.125rem; line-height: 1.75rem; }
                .text-xl { font-size: 1.25rem; line-height: 1.75rem; }
                .font-medium { font-weight: 500; }
                .font-semibold { font-weight: 600; }
                .font-bold { font-weight: 700; }
                .text-center { text-align: center; }
                .text-left { text-align: left; }
                .shadow-sm { box-shadow: var(--shadow-sm); }
                .shadow-md { box-shadow: var(--shadow-md); }
                .opacity-60 { opacity: 0.6; }
                .opacity-75 { opacity: 0.75; }
            }
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastRenderKey: String?
        var onContentHeightChange: ((CGFloat) -> Void)?
        var onNetworkOriginRequest: ((String) -> Void)?
        var networkOrigins: [String] = []
        var allowAllNetworkRequests = false

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "ginnyNetworkPolicy",
                  let payload = message.body as? [String: Any],
                  let originValue = payload["origin"] as? String,
                  let url = URL(string: originValue),
                  let origin = ArtefactNetworkPolicy.origin(from: url),
                  !allowAllNetworkRequests,
                  !networkOrigins.contains(origin)
            else { return }

            Task { @MainActor [weak self] in
                self?.onNetworkOriginRequest?(origin)
            }
        }

        @MainActor
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(
                "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
            ) { [weak self] result, _ in
                guard let height = result as? NSNumber else { return }
                self?.onContentHeightChange?(max(1, CGFloat(height.doubleValue)))
            }
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType != .other else {
                decisionHandler(.allow)
                return
            }

            if allowAllNetworkRequests,
               let url = navigationAction.request.url,
               ArtefactNetworkPolicy.origin(from: url) != nil {
                decisionHandler(.allow)
                return
            }

            guard let url = navigationAction.request.url,
                  let origin = ArtefactNetworkPolicy.origin(from: url),
                  networkOrigins.contains(origin)
            else {
                if let url = navigationAction.request.url,
                   let origin = ArtefactNetworkPolicy.origin(from: url) {
                    onNetworkOriginRequest?(origin)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

private enum GinnyThemeKeyDefaults {
    static let cssVariables: [String: String] = [
        "background": "#1e1e21",
        "foreground": "#ffffff",
        "card": "#323238",
        "card-foreground": "#ffffff",
        "popover": "#1e1e21",
        "popover-foreground": "#ffffff",
        "primary": "#00ffff",
        "primary-foreground": "#1e1e21",
        "secondary": "#323238",
        "secondary-foreground": "#ffffff",
        "muted": "#28282c",
        "muted-foreground": "#a9a9a9",
        "accent": "#323238",
        "accent-foreground": "#ffffff",
        "destructive": "#8c1e1e",
        "destructive-foreground": "#fff0f0",
        "border": "#323237",
        "input": "#1e1e21",
        "ring": "#00ffff",
        "sidebar": "#1c1c1f",
        "sidebar-foreground": "#ffffff",
        "sidebar-primary": "#00ffff",
        "sidebar-primary-foreground": "#1c1c1f",
        "sidebar-accent": "#323238",
        "sidebar-accent-foreground": "#ffffff",
        "sidebar-border": "#323237",
        "sidebar-ring": "#00ffff",
        "radius": "0.625rem"
    ]
}
