import SwiftStreamingMarkdown
import SwiftUI

struct ChatView: View {
    private let dependencies: AppDependencies

    @StateObject private var session: ChatSession
    @StateObject private var settings: ProviderSettings
    @State private var draft = ""
    @State private var activeResponse: ActiveResponse?
    @State private var generationTask: Task<Void, Never>?
    @State private var showsSettings = false

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        _session = StateObject(wrappedValue: ChatSession())
        _settings = StateObject(
            wrappedValue: ProviderSettings(credentialStore: dependencies.credentialStore)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(displayedMessages, id: \.id) { message in
                        ChatMessageView(message: message)
                    }

                    if let activeResponse {
                        StreamedMarkdownView(
                            source: activeResponse.source,
                            config: .default.withTextAnimation(.characterStreaming)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }

                    if let errorMessage = session.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask something", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)

                Button("Send", action: send)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        session.isGenerating
                            || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            .padding()
        }
        .navigationTitle("Conversation")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Provider", systemImage: "gearshape") {
                    showsSettings = true
                }
                .accessibilityLabel("Provider settings")
            }
        }
        .onChange(of: session.streamingText) { _, snapshot in
            activeResponse?.source.yield(snapshot)
        }
        .onDisappear {
            generationTask?.cancel()
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                ProviderSettingsView(settings: settings)
            }
        }
    }

    private var displayedMessages: [Message] {
        guard activeResponse != nil,
              session.conversation.messages.last?.role == .assistant
        else {
            return session.conversation.messages
        }
        return Array(session.conversation.messages.dropLast())
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty,
              !session.isGenerating,
              settings.save(),
              let configuration = settings.configuration
        else {
            if settings.configuration == nil {
                showsSettings = true
            }
            return
        }

        draft = ""
        session.configure(provider: dependencies.makeProvider(for: configuration))
        let response = ActiveResponse()
        activeResponse = response

        generationTask = Task { @MainActor in
            await session.send(prompt)
            response.source.finish()
            activeResponse = nil
            generationTask = nil
        }
    }
}

@MainActor
private struct ActiveResponse {
    let source = ChatResponseSource()
}

private struct ChatMessageView: View {
    let message: Message

    var body: some View {
        Group {
            if message.role == .user {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                MarkdownView(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    private var text: String {
        message.blocks.map(\.payload).joined()
    }
}

private struct ProviderSettingsView: View {
    @ObservedObject var settings: ProviderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("OpenAI-compatible provider") {
                TextField("Endpoint", text: $settings.endpointText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Model", text: $settings.modelText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API key or provider token", text: $settings.credentialText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Text("Credentials are stored in the system Keychain. Localhost HTTP endpoints are supported for local providers.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let validationMessage = settings.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Provider")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if settings.save() {
                        dismiss()
                    }
                }
            }
        }
    }
}
