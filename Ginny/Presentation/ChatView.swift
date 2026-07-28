import SwiftStreamingMarkdown
import SwiftUI

struct ChatView: View {
    private let dependencies: AppDependencies
    @ObservedObject private var themeStore: ThemeStore
    @Environment(\.ginnyTheme) private var theme

    @StateObject private var session: ChatSession
    @StateObject private var settings: ProviderSettings
    @State private var draft = ""
    @State private var activeResponse: ActiveResponse?
    @State private var generationTask: Task<Void, Never>?
    @State private var showsSettings = false

    init(
        dependencies: AppDependencies = .live,
        themeStore: ThemeStore = ThemeStore()
    ) {
        self.dependencies = dependencies
        _themeStore = ObservedObject(wrappedValue: themeStore)
        _session = StateObject(wrappedValue: ChatSession())
        _settings = StateObject(
            wrappedValue: ProviderSettings(credentialStore: dependencies.credentialStore)
        )
    }

    var body: some View {
        ZStack {
            theme.color("background")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ChatHeader(
                                themeStore: themeStore,
                                showsSettings: $showsSettings
                            )

                            if displayedMessages.isEmpty, activeResponse == nil {
                                EmptyConversationView()
                            } else {
                                LazyVStack(alignment: .leading, spacing: 20) {
                                    ForEach(displayedMessages, id: \.id) { message in
                                        ChatMessageView(
                                            message: message,
                                            markdownConfig: markdownConfig
                                        )
                                        .id(message.id)
                                    }

                                    if let activeResponse {
                                        StreamedMarkdownView(
                                            source: activeResponse.source,
                                            config: markdownConfig.withTextAnimation(.characterStreaming)
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id("active-response")
                                    }

                                    if let errorMessage = session.errorMessage {
                                        Text(errorMessage)
                                            .font(.footnote)
                                            .foregroundStyle(theme.color("text.error"))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(14)
                                            .background(theme.color("red.bg").opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .id("error")
                                    }
                                }
                                .padding(.bottom, 24)
                            }
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: session.streamingText) { _, _ in
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo("active-response", anchor: .bottom)
                        }
                    }
                    .onChange(of: session.conversation.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(session.conversation.messages.last?.id, anchor: .bottom)
                        }
                    }
                }

                ComposerView(
                    draft: $draft,
                    isGenerating: session.isGenerating,
                    themeName: themeStore.displayName(for: themeStore.selectedThemeID),
                    send: send
                )
                .frame(height: 116)
            }
        }
        .foregroundStyle(theme.color("text.body"))
        .toolbar(.hidden, for: .navigationBar)
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
            .environment(\.ginnyTheme, theme)
            .preferredColorScheme(theme.mode.colorScheme)
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

    private var markdownConfig: MarkdownRenderConfig {
        let base = MarkdownRenderConfig.default

        return base
            .withParagraphStyle(value: .init(
                textFonts: base.paragraphStyle.textFonts,
                textColor: theme.color("markdown.paragraph")
            ))
            .withBlockQuoteStyle(value: .init(
                textFonts: base.blockQuoteStyle.textFonts,
                textColor: theme.color("markdown.block_quote")
            ))
            .withHeadingStyle(value: .init(
                h1Font: base.headingStyle.h1Font,
                h2Font: base.headingStyle.h2Font,
                h3Font: base.headingStyle.h3Font,
                h4Font: base.headingStyle.h4Font,
                h5Font: base.headingStyle.h5Font,
                h6Font: base.headingStyle.h6Font,
                textColor: theme.color("markdown.heading.foreground")
            ))
            .withOrderedListStyle(value: .init(
                textFonts: base.orderedListStyle.textFonts,
                textColor: theme.color("markdown.list_bullet")
            ))
            .withInlineStyle(value: .init(
                boldTextColor: theme.color("markdown.strong"),
                linkTextFont: base.inlineStyle.linkTextFont,
                linkTextColor: theme.color("markdown.link_text"),
                codeTextFont: base.inlineStyle.codeTextFont,
                codeTextColor: theme.color("markdown.inline_code.fg"),
                codeBackgroundColor: theme.color("markdown.inline_code.bg"),
                codeUnderlineColor: theme.color("markdown.code_fence.border")
            ))
            .withThematicBreakColor(value: theme.color("markdown.thematic_break"))
            .withBlockSpacing(value: 16)
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
private struct ChatHeader: View {
    @ObservedObject var themeStore: ThemeStore
    @Binding var showsSettings: Bool
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Section("Theme") {
                    ForEach(themeStore.availableThemeIDs, id: \.self) { themeID in
                        Button {
                            themeStore.select(themeID: themeID)
                        } label: {
                            if themeStore.selectedThemeID == themeID {
                                Label(themeStore.displayName(for: themeID), systemImage: "checkmark")
                            } else {
                                Text(themeStore.displayName(for: themeID))
                            }
                        }
                    }
                }
            } label: {
                HeaderIconButton(systemImage: "line.3.horizontal")
            }
            .accessibilityLabel("Themes")

            VStack(alignment: .leading, spacing: 2) {
                Text("Ginny")
                    .font(.headline)
                Text(themeStore.displayName(for: themeStore.selectedThemeID))
                    .font(.caption)
                    .foregroundStyle(theme.color("text.muted"))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                showsSettings = true
            } label: {
                HeaderIconButton(systemImage: "gearshape")
            }
            .accessibilityLabel("Provider settings")
        }
        .padding(.top, 12)
        .padding(.bottom, 28)
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44)
            .foregroundStyle(theme.color("text.body"))
            .background(theme.color("secondary"), in: Circle())
            .overlay {
                Circle()
                    .stroke(theme.color("border"), lineWidth: 1)
            }
    }
}

private struct EmptyConversationView: View {
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.color("primary"))
                .accessibilityHidden(true)

            Text("A quiet place to think.")
                .font(.system(.title2, design: .serif, weight: .medium))
                .multilineTextAlignment(.center)

            Text("Ask a question, sketch an idea, or follow a thread.")
                .font(.subheadline)
                .foregroundStyle(theme.color("text.muted"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 128)
        .padding(.bottom, 220)
    }
}

private struct ComposerView: View {
    @Binding var draft: String
    let isGenerating: Bool
    let themeName: String
    let send: () -> Void
    @Environment(\.ginnyTheme) private var theme

    private var canSend: Bool {
        !isGenerating && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(theme.color("text.body"))
                        .background(theme.color("secondary"), in: Circle())
                }
                .accessibilityLabel("Add attachment")

                TextField("Start a message", text: $draft)
                    .font(.body)
                    .frame(height: 44)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: isGenerating ? "stop" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(theme.color("primary_foreground"))
                        .background(theme.color("primary"), in: Circle())
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.38)
                .accessibilityLabel(isGenerating ? "Stop generating" : "Send message")
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(isGenerating ? theme.color("primary") : theme.color("text.muted"))
                    .frame(width: 6, height: 6)
                Text(isGenerating ? "Thinking" : "Ready")
                Text("·")
                Text(themeName)
            }
            .font(.caption)
            .foregroundStyle(theme.color("text.muted"))
            .padding(.leading, 54)
        }
        .padding(12)
        .frame(height: 116, alignment: .top)
        .background(theme.color("card"), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(theme.color("border"), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

@MainActor
private struct ActiveResponse {
    let source = ChatResponseSource()
}

private struct ChatMessageView: View {
    let message: Message
    let markdownConfig: MarkdownRenderConfig
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Group {
            if message.role == .user {
                Text(text)
                    .font(.body)
                    .foregroundStyle(theme.color("pill.custom.fg"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(theme.color("pill.custom.bg"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                MarkdownView(text: text, config: markdownConfig)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var text: String {
        message.blocks.map(\.payload).joined()
    }
}

private struct ProviderSettingsView: View {
    @ObservedObject var settings: ProviderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme

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
                .foregroundStyle(theme.color("text.muted"))

            if let validationMessage = settings.validationMessage {
                Text(validationMessage)
                    .foregroundStyle(theme.color("text.error"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
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
