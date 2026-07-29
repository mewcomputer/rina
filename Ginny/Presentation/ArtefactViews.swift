import SwiftUI
import WebKit

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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var section: WorkspaceSection = .artefacts
    @State private var selectedArtefact: Artefact?
    @State private var selectedSkill: Skill?

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
                    Button {
                        if section == .artefacts {
                            createArtefact()
                        } else {
                            createSkill()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(section == .artefacts ? "New artefact" : "New skill")
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
        .tint(theme.color("primary"))
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
                        }
                    } icon: {
                        Image(systemName: artefact.kind.systemImage)
                            .foregroundStyle(theme.color("primary"))
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
}

private enum WorkspaceSection: CaseIterable {
    case artefacts
    case skills

    var title: String {
        switch self {
        case .artefacts: "Artefacts"
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

    init(artefact: Artefact, onSave: @escaping (Artefact) -> Void) {
        self.initialArtefact = artefact
        self.onSave = onSave
        _title = State(initialValue: artefact.title)
        _source = State(initialValue: artefact.currentRevision?.source ?? "")
        _mode = State(initialValue: artefact.kind == .web || artefact.kind == .inlineWeb ? .preview : .source)
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
                }
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if isWebArtefact, mode == .preview {
            WebArtefactPreview(html: source, isInline: initialArtefact.kind == .inlineWeb)
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

    private func save() {
        var artefact = initialArtefact
        artefact.setTitle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled artefact" : title)
        _ = artefact.checkpoint(
            source: source,
            renderedContent: isWebArtefact ? source : nil,
            metadata: ["edited": "true"]
        )
        onSave(artefact)
        dismiss()
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
    let html: String
    let isInline: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(Self.document(for: html, isInline: isInline), baseURL: nil)
    }

    static func document(for content: String, isInline: Bool) -> String {
        let viewport = isInline ? "width=device-width, initial-scale=1.0" : "width=device-width, initial-scale=1.0"
        let body = content.localizedCaseInsensitiveContains("<html")
            ? content
            : "<body>\(content)</body>"
        return """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="\(viewport)">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: blob:;">
            <style>
                :root {
                    --background: oklch(0.985 0.008 260);
                    --foreground: oklch(0.22 0.018 260);
                    --card: oklch(0.995 0.006 260);
                    --muted: oklch(0.94 0.012 260);
                    --muted-foreground: oklch(0.48 0.02 260);
                    --primary: oklch(0.57 0.16 265);
                    --primary-foreground: oklch(0.99 0.005 260);
                    --border: oklch(0.86 0.018 260);
                    --input: oklch(0.9 0.015 260);
                    --ring: oklch(0.68 0.13 265);
                    --radius: 0.75rem;
                }
                * { box-sizing: border-box; }
                html, body { margin: 0; min-height: 100%; }
                body {
                    padding: 20px;
                    color: var(--foreground);
                    background: var(--background);
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                }
                button, input, textarea, select {
                    font: inherit;
                    color: inherit;
                }
                button {
                    border: 1px solid var(--border);
                    border-radius: var(--radius);
                    background: var(--card);
                    padding: 0.65rem 0.9rem;
                }
                button:focus-visible, input:focus-visible, textarea:focus-visible, select:focus-visible {
                    outline: 2px solid var(--ring);
                    outline-offset: 2px;
                }
            </style>
        </head>
        \(body)
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}
