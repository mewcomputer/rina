import SwiftStreamingMarkdown
import SwiftUI

struct ChatView: View {
    private let dependencies: AppDependencies
    @ObservedObject private var themeStore: ThemeStore
    @Environment(\.ginnyTheme) private var theme

    @StateObject private var session: ChatSession
    @StateObject private var settings: ProviderSettings
    @StateObject private var history: SessionHistoryStore
    @State private var draft = ""
    @State private var activeResponse: ActiveResponse?
    @State private var generationTask: Task<Void, Never>?
    @State private var showsSettings = false
    @State private var isSidebarPresented = false
    @State private var sidebarDragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        _history = StateObject(wrappedValue: SessionHistoryStore())
    }

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = min(340, geometry.size.width * 0.86)
            let progress = sidebarProgress(for: sidebarWidth)

            ZStack(alignment: .leading) {
                theme.color("background")
                    .ignoresSafeArea()

                chatSurface
                    .offset(x: progress * sidebarWidth)
                    .simultaneousGesture(edgeOpenGesture(width: sidebarWidth))

                if progress > 0 {
                    Color.black.opacity(0.42 * progress)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { setSidebarPresented(false) }
                        .accessibilityHidden(true)
                }

                if isSidebarPresented || sidebarDragOffset > 0 {
                    SessionSidebar(
                        history: history,
                        themeStore: themeStore,
                        currentConversationID: session.conversation.id,
                        onSelect: selectConversation,
                        onNewConversation: startNewConversation,
                        onSettings: { showsSettings = true },
                        onClose: { setSidebarPresented(false) }
                    )
                    .frame(width: sidebarWidth)
                    .offset(x: drawerOffset(for: sidebarWidth))
                    .simultaneousGesture(drawerCloseGesture(width: sidebarWidth))
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var chatSurface: some View {
        ZStack {
            theme.color("background")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ChatHeader(onOpenSidebar: { setSidebarPresented(true) })
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .zIndex(1)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
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
                                            .ginnyGlass(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous),
                                                prominence: .subtle
                                            )
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
                    send: send
                )
                .frame(height: 88)
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

    private func sidebarProgress(for width: CGFloat) -> CGFloat {
        let progress: CGFloat
        if isSidebarPresented {
            progress = 1 + sidebarDragOffset / width
        } else {
            progress = sidebarDragOffset / width
        }
        return min(1, max(0, progress))
    }

    private func drawerOffset(for width: CGFloat) -> CGFloat {
        if isSidebarPresented {
            return min(0, sidebarDragOffset)
        }
        return -width + max(0, sidebarDragOffset)
    }

    private func edgeOpenGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isSidebarPresented,
                      value.startLocation.x <= 32,
                      value.translation.width > 0
                else { return }
                sidebarDragOffset = min(width, value.translation.width)
            }
            .onEnded { value in
                guard !isSidebarPresented, value.startLocation.x <= 32 else { return }
                let projected = value.predictedEndTranslation.width
                setSidebarPresented(projected > width * 0.32)
            }
    }

    private func drawerCloseGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard isSidebarPresented,
                      value.startLocation.x >= width - 64,
                      value.translation.width < 0
                else { return }
                sidebarDragOffset = max(-width, value.translation.width)
            }
            .onEnded { value in
                guard isSidebarPresented, value.startLocation.x >= width - 64 else { return }
                let projected = value.predictedEndTranslation.width
                setSidebarPresented(projected < -width * 0.32)
            }
    }

    private func setSidebarPresented(_ presented: Bool) {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.18)
            : .interactiveSpring(response: 0.34, dampingFraction: 0.86)
        withAnimation(animation) {
            isSidebarPresented = presented
            sidebarDragOffset = 0
        }
    }

    private func selectConversation(_ conversation: Conversation) {
        guard !session.isGenerating else { return }
        session.load(conversation: conversation)
        activeResponse = nil
        setSidebarPresented(false)
    }

    private func startNewConversation() {
        guard !session.isGenerating else { return }
        session.reset()
        activeResponse = nil
        draft = ""
        setSidebarPresented(false)
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
            if session.conversation.generationState == .completed {
                history.save(session.conversation)
            }
            response.source.finish()
            activeResponse = nil
            generationTask = nil
        }
    }
}

@MainActor
private struct ChatHeader: View {
    let onOpenSidebar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenSidebar) {
                HeaderIconButton(systemImage: "line.3.horizontal")
            }
            .accessibilityLabel("Open session history")

            Text("Ginny")
                .font(.headline)

            Spacer(minLength: 8)
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

@MainActor
private struct SessionSidebar: View {
    @ObservedObject var history: SessionHistoryStore
    @ObservedObject var themeStore: ThemeStore
    let currentConversationID: ConversationID
    let onSelect: (Conversation) -> Void
    let onNewConversation: () -> Void
    let onSettings: () -> Void
    let onClose: () -> Void
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sessions")
                        .font(.system(.title2, design: .serif, weight: .medium))
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(theme.color("text.body"))
                        .ginnyGlass(Circle(), prominence: .subtle)
                }
                .accessibilityLabel("Close session history")
            }

            Button(action: onNewConversation) {
                Label("New session", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            }
            .foregroundStyle(theme.color("primary_foreground"))
            .background(theme.color("primary"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHint("Starts a blank conversation")

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
                HStack(spacing: 10) {
                    Image(systemName: "paintpalette")
                    Text("Appearance")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.color("text.body"))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .ginnyGlass(
                    RoundedRectangle(cornerRadius: 18, style: .continuous),
                    prominence: .subtle
                )
            }
            .accessibilityLabel("Appearance and theme")

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if history.conversations.isEmpty {
                        Text("No sessions yet.")
                            .font(.subheadline)
                            .foregroundStyle(theme.color("text.muted"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(history.conversations, id: \.id) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                SessionHistoryRow(
                                    title: history.title(for: conversation),
                                    isSelected: conversation.id == currentConversationID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: onSettings) {
                Label("Settings", systemImage: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
            }
            .foregroundStyle(theme.color("text.body"))
            .ginnyGlass(
                RoundedRectangle(cornerRadius: 18, style: .continuous),
                prominence: .subtle
            )
            .accessibilityLabel("Provider settings")
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 10)
        .safeAreaPadding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .ginnyGlass(Rectangle(), prominence: .elevated)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.color("border").opacity(0.62))
                .frame(width: 1)
        }
    }
}

private struct SessionHistoryRow: View {
    let title: String
    let isSelected: Bool
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if isSelected {
                Circle()
                    .fill(theme.color("primary"))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .ginnyGlass(
            RoundedRectangle(cornerRadius: 16, style: .continuous),
            prominence: isSelected ? .subtle : .subtle
        )
        .opacity(isSelected ? 1 : 0.88)
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
            .ginnyGlass(Circle(), prominence: .subtle)
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

            Text("Start here.")
                .font(.system(.title2, design: .serif, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 128)
        .padding(.bottom, 220)
    }
}

private struct ComposerView: View {
    @Binding var draft: String
    let isGenerating: Bool
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
                        .ginnyGlass(Circle(), prominence: .subtle)
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

        }
        .padding(12)
        .frame(height: 88, alignment: .top)
        .ginnyGlass(
            RoundedRectangle(cornerRadius: 28, style: .continuous),
            prominence: .elevated
        )
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
                    .ginnyGlass(
                        RoundedRectangle(cornerRadius: 20, style: .continuous),
                        prominence: .subtle
                    )
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
