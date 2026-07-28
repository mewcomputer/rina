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
            wrappedValue: ProviderSettings(
                credentialStore: dependencies.credentialStore,
                modelCatalog: dependencies.modelCatalog
            )
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
                        onSettings: { showsSettings = true }
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
        .task {
            await settings.refreshModels()
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
                ZStack(alignment: .top) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if displayedMessages.isEmpty, activeResponse == nil {
                                    EmptyConversationView()
                                } else {
                                    VStack(alignment: .leading, spacing: 20) {
                                        ForEach(displayedItems) { item in
                                            switch item {
                                            case .message(let message):
                                                ChatMessageView(
                                                    message: message,
                                                    markdownConfig: markdownConfig
                                                )
                                                .id(item.id)
                                            case .toolActivity(let message, let group):
                                                ChatMessageView(
                                                    message: message,
                                                    toolActivity: group,
                                                    markdownConfig: markdownConfig
                                                )
                                                .id(item.id)
                                            }
                                        }

                                        if let activeResponse {
                                            StreamedMarkdownView(
                                                source: activeResponse.source,
                                                config: markdownConfig.withTextAnimation(.fastFade)
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
                            .padding(.top, 72)
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
                                proxy.scrollTo(displayedItems.last?.id, anchor: .bottom)
                            }
                        }
                    }

                    ChatHeader(
                        title: conversationTitle,
                        onOpenSidebar: { setSidebarPresented(true) }
                    )
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .background {
                        LinearGradient(
                            colors: [
                                theme.color("background").opacity(0.94),
                                theme.color("background").opacity(0.68),
                                theme.color("background").opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .zIndex(1)
                }
                .frame(maxHeight: .infinity)

                ComposerView(
                    draft: $draft,
                    settings: settings,
                    isGenerating: session.isGenerating,
                    send: send,
                    cancel: cancel,
                    openSettings: { showsSettings = true }
                )
                .frame(height: 100)
            }
        }
    }

    private var conversationTitle: String {
        if let storedConversation = history.conversations.first(where: {
            $0.id == session.conversation.id
        }) {
            return history.title(for: storedConversation)
        }
        return history.title(for: session.conversation)
    }

    private var displayedMessages: [Message] {
        guard activeResponse != nil,
              let lastMessage = session.conversation.messages.last,
              lastMessage.role == .assistant,
              !lastMessage.blocks.contains(where: { $0.kind == .toolCall })
        else {
            return session.conversation.messages
        }
        return Array(session.conversation.messages.dropLast())
    }

    private var displayedItems: [ChatDisplayItem] {
        var items: [ChatDisplayItem] = []
        var index = 0

        while index < displayedMessages.count {
            let message = displayedMessages[index]
            let calls = message.blocks.filter { $0.kind == .toolCall }

            guard message.role == .assistant, !calls.isEmpty else {
                items.append(.message(message))
                index += 1
                continue
            }

            var results: [ContentBlock] = []
            var nextIndex = index + 1
            while nextIndex < displayedMessages.count,
                  displayedMessages[nextIndex].role == .tool
            {
                results.append(contentsOf: displayedMessages[nextIndex].blocks.filter {
                    $0.kind == .toolResult
                })
                nextIndex += 1
            }

            items.append(
                .toolActivity(
                    message: message,
                    group: ToolActivityGroup(calls: calls, results: results)
                )
            )
            index = nextIndex
        }

        return items
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
            let completedConversation = session.conversation
            if [.completed, .cancelled, .failed].contains(completedConversation.generationState) {
                history.save(completedConversation)
                if completedConversation.generationState == .completed {
                    Task { @MainActor in
                        await history.generateTitle(for: completedConversation)
                    }
                }
            }
            response.source.finish()
            activeResponse = nil
            generationTask = nil
        }
    }

    private func cancel() {
        session.cancel()
        generationTask?.cancel()
    }
}

private enum ChatDisplayItem: Identifiable {
    case message(Message)
    case toolActivity(message: Message, group: ToolActivityGroup)

    var id: MessageID {
        switch self {
        case .message(let message), .toolActivity(let message, _):
            message.id
        }
    }
}

@MainActor
private struct ChatHeader: View {
    let title: String
    let onOpenSidebar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenSidebar) {
                HeaderIconButton(systemImage: "line.3.horizontal")
            }
            .accessibilityLabel("Open session history")

            Text(title)
                .font(.headline)
                .lineLimit(1)

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
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sessions")
                .font(.system(.title2, design: .serif, weight: .medium))

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
            .background(
                theme.color("sidebar_accent"),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .accessibilityLabel("Provider settings")
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 10)
        .safeAreaPadding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.color("sidebar.background").ignoresSafeArea())
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
        .background(
            isSelected ? theme.color("sidebar_accent") : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
    @ObservedObject var settings: ProviderSettings
    let isGenerating: Bool
    let send: () -> Void
    let cancel: () -> Void
    let openSettings: () -> Void
    @Environment(\.ginnyTheme) private var theme

    private var canSubmit: Bool {
        isGenerating || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Start a message", text: $draft)
                .font(.body)
                .frame(height: 34)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit(send)

            HStack(spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(theme.color("text.body"))
                        .ginnyGlass(Circle(), prominence: .subtle)
                }
                .accessibilityLabel("Add attachment")

                ServiceModelMenu(settings: settings, openSettings: openSettings)

                Spacer(minLength: 0)

                Button(action: isGenerating ? cancel : send) {
                    Image(systemName: isGenerating ? "stop" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(theme.color("primary_foreground"))
                        .background(theme.color("primary"), in: Circle())
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.38)
                .accessibilityLabel(isGenerating ? "Stop generating" : "Send message")
            }
        }
        .padding(12)
        .frame(height: 100, alignment: .top)
        .ginnyGlass(
            RoundedRectangle(cornerRadius: 28, style: .continuous),
            prominence: .elevated
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct ServiceModelMenu: View {
    @ObservedObject var settings: ProviderSettings
    let openSettings: () -> Void
    @Environment(\.ginnyTheme) private var theme
    @State private var showsModelPicker = false

    private var modelLabel: String {
        let model = settings.modelText.isEmpty ? "Choose model" : settings.modelText
        return "\(settings.provider.displayName) · \(model)"
    }

    var body: some View {
        Button {
            showsModelPicker = true
        } label: {
            HStack(spacing: 5) {
                Text(modelLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.color("text.body"))
            .padding(.horizontal, 11)
            .frame(height: 36)
            .ginnyGlass(Capsule(), prominence: .subtle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose service and model")
        .accessibilityValue(modelLabel)
        .sheet(isPresented: $showsModelPicker) {
            ModelPickerSheet(settings: settings, openSettings: openSettings)
                .environment(\.ginnyTheme, theme)
                .preferredColorScheme(theme.mode.colorScheme)
        }
    }
}

private struct ModelPickerSheet: View {
    @ObservedObject var settings: ProviderSettings
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var searchText = ""
    @State private var selectedDetent: PresentationDetent = .large

    private var filteredModels: [ProviderModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return settings.availableModels }
        return settings.availableModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    servicePicker

                    if settings.isLoadingModels {
                        ProgressView("Loading models…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if filteredModels.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "cube.transparent")
                                .font(.title2)
                                .foregroundStyle(theme.color("text.muted"))
                            Text(searchText.isEmpty ? "No models available." : "No matching models.")
                                .foregroundStyle(theme.color("text.muted"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        ForEach(filteredModels) { model in
                            Button {
                                settings.selectModel(model.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model.displayName)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(theme.color("text.body"))
                                        if model.displayName != model.id {
                                            Text(model.id)
                                                .font(.caption)
                                                .foregroundStyle(theme.color("text.muted"))
                                        }
                                    }

                                    Spacer(minLength: 8)

                                    if settings.modelText == model.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(theme.color("primary"))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    settings.modelText == model.id
                                        ? theme.color("card")
                                        : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !settings.thinkingOptions.isEmpty {
                        thinkingPicker
                    }

                    Button {
                        dismiss()
                        openSettings()
                    } label: {
                        Text("Configure service")
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.color("primary"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .searchable(text: $searchText, prompt: "Search models")
            .navigationTitle("Select model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await settings.refreshModels() }
                    } label: {
                        if settings.isLoadingModels {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(settings.isLoadingModels)
                    .accessibilityLabel("Refresh models")
                }
            }
            .task {
                if settings.availableModels.isEmpty {
                    await settings.refreshModels()
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private var servicePicker: some View {
        Menu {
            ForEach(ProviderID.allCases, id: \.self) { provider in
                Button {
                    Task { await settings.selectProviderAndRefresh(provider) }
                } label: {
                    Label(
                        provider.displayName,
                        systemImage: settings.provider == provider ? "checkmark" : "circle"
                    )
                }
            }
        } label: {
            HStack {
                Label("Service", systemImage: "square.stack.3d.up")
                Spacer(minLength: 12)
                Text(settings.provider.displayName)
                    .foregroundStyle(theme.color("text.muted"))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.color("text.muted"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .ginnyGlass(
                RoundedRectangle(cornerRadius: 18, style: .continuous),
                prominence: .subtle
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Service")
        .accessibilityValue(settings.provider.displayName)
    }

    private var thinkingPicker: some View {
        Picker(
            "Thinking",
            selection: Binding(
                get: { settings.thinkingLevel },
                set: { settings.selectThinkingLevel($0) }
            )
        ) {
            ForEach(settings.thinkingOptions, id: \.self) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.menu)
        .tint(theme.color("text.muted"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .ginnyGlass(
            RoundedRectangle(cornerRadius: 18, style: .continuous),
            prominence: .subtle
        )
    }
}

@MainActor
private struct ActiveResponse {
    let source = ChatResponseSource()
}

private struct ChatMessageView: View {
    let message: Message
    let toolActivity: ToolActivityGroup?
    let markdownConfig: MarkdownRenderConfig
    @Environment(\.ginnyTheme) private var theme

    init(
        message: Message,
        toolActivity: ToolActivityGroup? = nil,
        markdownConfig: MarkdownRenderConfig
    ) {
        self.message = message
        self.toolActivity = toolActivity
        self.markdownConfig = markdownConfig
    }

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
            } else if message.role == .tool {
                ToolResultGroupView(results: toolResults)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if !toolCalls.isEmpty {
                        ToolActivityGroupView(
                            group: toolActivity
                                ?? ToolActivityGroup(calls: toolCalls, results: [])
                        )
                    }
                    if !text.isEmpty {
                        MarkdownView(text: text, config: markdownConfig)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var text: String {
        message.blocks
            .filter { $0.kind == .text }
            .map(\.payload)
            .joined()
    }

    private var toolCalls: [ContentBlock] {
        message.blocks.filter { $0.kind == .toolCall }
    }

    private var toolResults: [ContentBlock] {
        message.blocks.filter { $0.kind == .toolResult }
    }
}

private struct ToolActivityGroupView: View {
    let group: ToolActivityGroup
    @Environment(\.ginnyTheme) private var theme
    @State private var isExpanded = false

    private var containsError: Bool {
        group.activities.contains { $0.result?.attributes["isError"] == "true" }
            || group.unmatchedResults.contains { $0.attributes["isError"] == "true" }
    }

    private var isPending: Bool {
        group.activities.contains { !$0.call.isComplete || $0.result == nil }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.activities) { activity in
                    ToolActivityRow(activity: activity)
                }
                ForEach(group.unmatchedResults, id: \.id) { result in
                    ToolResultRow(result: result)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.subheadline.weight(.medium))
                Text(
                    group.activities.count == 1
                        ? "Tool activity"
                        : "\(group.activities.count) tool activities"
                )
                    .font(.subheadline.weight(.medium))
                Spacer()
                if isPending {
                    ProgressView()
                        .controlSize(.small)
                } else if containsError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.color("text.error"))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.color("text.success"))
                }
            }
        }
        .tint(theme.color("text.body"))
        .padding(14)
        .background(
            theme.color("card").opacity(0.3),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private struct ToolActivityRow: View {
    let activity: ToolActivity
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ToolCallRow(call: activity.call)

            if let result = activity.result {
                Divider()
                    .overlay(theme.color("border").opacity(0.7))
                ToolResultRow(result: result)
            }
        }
    }
}

private struct ToolCallRow: View {
    let call: ContentBlock
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        let name = call.attributes["name"] ?? "Tool"

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: call.isComplete ? "checkmark" : "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        call.isComplete
                            ? theme.color("text.success")
                            : theme.color("text.muted")
                    )
                Text(name.isEmpty ? "Tool" : name)
                    .font(.subheadline.weight(.medium))
            }

            if !call.payload.isEmpty {
                Text(call.payload)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.color("text.muted"))
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ToolResultRow: View {
    let result: ContentBlock
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Result", systemImage: "arrow.turn.down.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    result.attributes["isError"] == "true"
                        ? theme.color("text.error")
                        : theme.color("text.muted")
                )

            Text(result.payload)
                .font(.caption.monospaced())
                .foregroundStyle(theme.color("text.muted"))
                .textSelection(.enabled)
        }
    }
}

private struct ToolResultGroupView: View {
    let results: [ContentBlock]
    @Environment(\.ginnyTheme) private var theme
    @State private var isExpanded = false

    private var containsError: Bool {
        results.contains { $0.attributes["isError"] == "true" }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(results, id: \.id) { result in
                    ToolResultRow(result: result)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: containsError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                Text(results.count == 1 ? "Tool result" : "Tool results")
                    .font(.subheadline.weight(.medium))
            }
        }
        .tint(containsError ? theme.color("text.error") : theme.color("text.body"))
        .padding(14)
        .background(
            (containsError ? theme.color("surface.error") : theme.color("card")).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private struct ProviderSettingsView: View {
    @ObservedObject var settings: ProviderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.provider) { _, provider in
                    settings.selectProvider(provider)
                }

                TextField("Base URL", text: $settings.endpointText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if settings.provider == .umans, !settings.availableModels.isEmpty {
                    Picker("Model", selection: $settings.modelText) {
                        ForEach(settings.availableModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .onChange(of: settings.modelText) { _, model in
                        settings.selectModel(model)
                    }
                } else {
                    TextField("Model", text: $settings.modelText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if settings.provider == .umans {
                    HStack {
                        if settings.isLoadingModels {
                            ProgressView()
                        }
                        Button("Refresh models") {
                            Task { await settings.refreshModels() }
                        }
                        .disabled(settings.isLoadingModels)
                    }
                }

                SecureField("API key", text: $settings.credentialText)
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

            if let catalogMessage = settings.catalogMessage {
                Text(catalogMessage)
                    .foregroundStyle(theme.color("text.error"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
        .navigationTitle("Provider")
        .task {
            await settings.refreshModels()
        }
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
