import SwiftUI

private extension SourceExtractionState {
    var contextDisplayName: String {
        switch self {
        case .pending: "Pending extraction"
        case .extracting: "Extracting"
        case .ready: "Ready"
        case .partiallyReady: "Partially extracted"
        case .failed: "Extraction failed"
        }
    }
}

struct ContextPickerButton: View {
    @ObservedObject var store: ContextStore
    @Binding var selectedContextID: ContextID?
    let messages: [Message]
    let artefacts: [Artefact]
    @Environment(\.ginnyTheme) private var theme
    @State private var showsPicker = false

    private var label: String {
        store.contexts.first { $0.id == selectedContextID }?.name ?? "Context"
    }

    var body: some View {
        Button {
            showsPicker = true
        } label: {
            Label(label, systemImage: "rectangle.stack")
                .lineLimit(1)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.color("text.body"))
                .padding(.horizontal, 11)
                .frame(height: 36)
                .ginnyGlass(Capsule(), prominence: .subtle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose context")
        .accessibilityValue(label)
        .accessibilityIdentifier("composer.contextPicker")
        .sheet(isPresented: $showsPicker) {
            ContextPickerSheet(
                store: store,
                selectedContextID: $selectedContextID,
                messages: messages,
                artefacts: artefacts
            )
            .environment(\.ginnyTheme, theme)
            .preferredColorScheme(theme.mode.colorScheme)
        }
    }
}

private struct ContextPickerSheet: View {
    @ObservedObject var store: ContextStore
    @Binding var selectedContextID: ContextID?
    let messages: [Message]
    let artefacts: [Artefact]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var editingContext: Context?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedContextID = nil
                        dismiss()
                    } label: {
                        contextRow(name: "No context", isSelected: selectedContextID == nil)
                    }
                    .buttonStyle(.plain)
                }

                Section("Saved contexts") {
                    if store.contexts.isEmpty {
                        Text("Create a context from messages, artefacts, or sources.")
                            .font(.footnote)
                            .foregroundStyle(theme.color("text.muted"))
                    } else {
                        ForEach(store.contexts) { context in
                            Button {
                                selectedContextID = context.id
                                dismiss()
                            } label: {
                                contextRow(
                                    name: context.name,
                                    detail: "\(context.members.count) items",
                                    isSelected: selectedContextID == context.id
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") {
                                    editingContext = context
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    if selectedContextID == context.id {
                                        selectedContextID = nil
                                    }
                                    store.remove(context)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create context")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            ContextEditorView(
                context: nil,
                store: store,
                messages: messages,
                artefacts: artefacts
            )
            .environment(\.ginnyTheme, theme)
        }
        .sheet(item: $editingContext) { context in
            ContextEditorView(
                context: context,
                store: store,
                messages: messages,
                artefacts: artefacts
            )
            .environment(\.ginnyTheme, theme)
        }
    }

    private func contextRow(
        name: String,
        detail: String? = nil,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(
                    isSelected
                        ? theme.color("primary")
                        : theme.color("text.muted")
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .foregroundStyle(theme.color("text.body"))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(theme.color("text.muted"))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct ContextEditorView: View {
    let context: Context?
    @ObservedObject var store: ContextStore
    let messages: [Message]
    let artefacts: [Artefact]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var name: String
    @State private var selectedMembers: Set<ContextMember>

    init(
        context: Context?,
        store: ContextStore,
        messages: [Message],
        artefacts: [Artefact]
    ) {
        self.context = context
        self.store = store
        self.messages = messages
        self.artefacts = artefacts
        _name = State(initialValue: context?.name ?? "")
        _selectedMembers = State(initialValue: Set(context?.members ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } header: {
                    Text("Context")
                }

                if !messages.isEmpty {
                    Section("Messages") {
                        ForEach(messages, id: \.id) { message in
                            Toggle(
                                isOn: binding(for: .message(message.id))
                            ) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(message.role.rawValue.capitalized)
                                    Text(messagePreview(message))
                                        .font(.caption)
                                        .foregroundStyle(theme.color("text.muted"))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                if !artefactRevisions.isEmpty {
                    Section("Artefact revisions") {
                        ForEach(artefacts) { artefact in
                            ForEach(artefact.revisions) { revision in
                                Toggle(
                                    isOn: binding(
                                        for: .artefactRevision(
                                            artefactID: artefact.id,
                                            revisionID: revision.id
                                        )
                                    )
                                ) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(artefact.title)
                                        Text("Revision \(revision.id.rawValue.rawValue.prefix(8))")
                                            .font(.caption)
                                            .foregroundStyle(theme.color("text.muted"))
                                    }
                                }
                            }
                        }
                    }
                }

                if !store.sources.isEmpty {
                    Section("Sources") {
                        ForEach(store.sources) { source in
                            Toggle(
                                isOn: binding(for: .source(source.id))
                            ) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.displayName)
                                    Text(source.extractionState.contextDisplayName)
                                        .font(.caption)
                                        .foregroundStyle(theme.color("text.muted"))
                                }
                            }
                            .disabled(source.extractedText == nil)
                        }
                    }
                }
            }
            .navigationTitle(context == nil ? "New context" : "Edit context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var artefactRevisions: [ArtefactRevision] {
        artefacts.flatMap(\.revisions)
    }

    private func binding(for member: ContextMember) -> Binding<Bool> {
        Binding(
            get: { selectedMembers.contains(member) },
            set: { isSelected in
                if isSelected {
                    selectedMembers.insert(member)
                } else {
                    selectedMembers.remove(member)
                }
            }
        )
    }

    private func messagePreview(_ message: Message) -> String {
        let text = message.blocks.map(\.payload).joined(separator: " ")
        return text.isEmpty ? "No text" : text
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageMembers = messages.map { ContextMember.message($0.id) }
            .filter(selectedMembers.contains)
        let artefactMembers = artefacts.flatMap { artefact in
                artefact.revisions.map {
                    ContextMember.artefactRevision(
                        artefactID: artefact.id,
                        revisionID: $0.id
                    )
                }
            }
            .filter(selectedMembers.contains)
        let sourceMembers = store.sources.map { ContextMember.source($0.id) }
                .filter(selectedMembers.contains)
        let members = messageMembers + artefactMembers + sourceMembers
        var updated = context ?? Context(name: trimmedName)
        updated.setName(trimmedName)
        updated.setMembers(members)
        store.save(updated)
        dismiss()
    }
}
