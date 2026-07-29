import SwiftStreamingMarkdown
import SwiftUI

struct ChatView: View {
    private let dependencies: AppDependencies
    @ObservedObject private var themeStore: ThemeStore
    @Environment(\.ginnyTheme) private var theme

    @StateObject private var session: ChatSession
    @StateObject private var settings: ProviderSettings
    @StateObject private var history: SessionHistoryStore
    @StateObject private var artefacts: ArtefactStore
    @StateObject private var contextStore: ContextStore
    @StateObject private var publicationStore: AtprotoPublicationStore
    @State private var draft = ""
    @State private var activeResponse: ActiveResponse?
    @State private var generationTask: Task<Void, Never>?
    @State private var showsSettings = false
    @State private var showsWorkspace = false
    @State private var showsSearch = false
    @State private var showsSharePreview = false
    @State private var selectedContextID: ContextID?
    @State private var isSidebarPresented = false
    @State private var sidebarDragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let composerReservedHeight: CGFloat = 198

    init(
        dependencies: AppDependencies,
        themeStore: ThemeStore = ThemeStore()
    ) {
        self.dependencies = dependencies
        _themeStore = ObservedObject(wrappedValue: themeStore)
        _session = StateObject(
            wrappedValue: ChatSession(
                toolRegistry: dependencies.makeToolRegistry(),
                persistence: { conversation in
                    try dependencies.conversationRepository.upsert(conversation)
                },
                citationPersistence: { citation in
                    try dependencies.citationRepository?.upsert(citation)
                },
                relationshipPersistence: { edge in
                    try dependencies.relationshipRepository.upsert(edge)
                },
                searchIndex: dependencies.searchIndex
            )
        )
        _settings = StateObject(
            wrappedValue: ProviderSettings(
                credentialStore: dependencies.credentialStore,
                modelCatalog: dependencies.modelCatalog
            )
        )
        _history = StateObject(
            wrappedValue: SessionHistoryStore(
                repository: dependencies.conversationRepository
            )
        )
        _artefacts = StateObject(
            wrappedValue: ArtefactStore(
                repository: dependencies.artefactRepository,
                searchIndex: dependencies.searchIndex
            )
        )
        _contextStore = StateObject(
            wrappedValue: ContextStore(
                contextRepository: dependencies.contextRepository,
                sourceRepository: dependencies.sourceRepository,
                searchIndex: dependencies.searchIndex
            )
        )
        _publicationStore = StateObject(wrappedValue: AtprotoPublicationStore())
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
                        onSearch: { showsSearch = true },
                        onWorkspace: { showsWorkspace = true },
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
            if snapshot.isEmpty {
                activeResponse?.source.reset()
            } else {
                activeResponse?.source.yield(snapshot)
            }
        }
        .onChange(of: session.streamingReasoningText) { _, _ in
            let snapshot = currentStreamingReasoningText
            if snapshot.isEmpty {
                activeResponse?.thinkingSource.reset()
            } else {
                activeResponse?.thinkingSource.yield(snapshot)
            }
        }
        .onChange(of: session.conversation.messages.count) { _, _ in
            artefacts.refresh()
            configureSelectedContext()
        }
        .onChange(of: selectedContextID) { _, _ in
            configureSelectedContext()
        }
        .onChange(of: contextStore.contexts) { _, _ in
            configureSelectedContext()
        }
        .onChange(of: contextStore.sources) { _, _ in
            configureSelectedContext()
        }
        .onChange(of: showsWorkspace) { _, isPresented in
            if !isPresented {
                contextStore.refresh()
            }
        }
        .onChange(of: artefacts.skills) { _, _ in
            session.configure(skillCatalog: artefacts.skillCatalog)
        }
        .onChange(of: settings.autoApproveArtefactWrites) { _, value in
            session.configure(autoApproveArtefactWrites: value)
            settings.persistArtefactPreferences()
        }
        .onChange(of: settings.allowAllArtefactWebRequests) { _, _ in
            settings.persistArtefactPreferences()
        }
        .onDisappear {
            generationTask?.cancel()
        }
        .task {
            session.configure(autoApproveArtefactWrites: settings.autoApproveArtefactWrites)
            await settings.refreshModels()
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                ProviderSettingsView(
                    settings: settings,
                    authService: dependencies.atprotoAuth,
                    themeStore: themeStore,
                    dataResetter: dependencies.localDataResetter,
                    onDataReset: resetLocalData
                )
            }
            .environment(\.ginnyTheme, theme)
            .preferredColorScheme(theme.mode.colorScheme)
        }
        .sheet(isPresented: $showsWorkspace) {
            WorkspaceLibraryView(
                store: artefacts,
                sourceImporter: dependencies.makeSourceImporter(),
                relationshipRepository: dependencies.relationshipRepository,
                sharingService: dependencies.atprotoSharing,
                publicationStore: publicationStore
            )
                .environment(\.ginnyTheme, theme)
                .preferredColorScheme(theme.mode.colorScheme)
        }
        .sheet(isPresented: $showsSearch) {
            WorkspaceSearchView(
                index: dependencies.searchIndex,
                conversations: history.conversations,
                artefacts: artefacts.artefacts,
                sources: contextStore.sources,
                contexts: contextStore.contexts,
                titleForConversation: history.title(for:),
                relationshipRepository: dependencies.relationshipRepository,
                openConversation: selectConversation,
                openWorkspace: { showsWorkspace = true },
                selectContext: { selectedContextID = $0 }
            )
            .environment(\.ginnyTheme, theme)
            .preferredColorScheme(theme.mode.colorScheme)
        }
        .sheet(isPresented: $showsSharePreview) {
            ConversationSharePreviewSheet(
                conversation: session.conversation,
                artefacts: artefacts.artefacts,
                publication: publicationStore.publications.first {
                    $0.collection == AtprotoRecordCollection.conversation
                        && $0.subjectID == session.conversation.id.rawValue.rawValue
                },
                sharingService: dependencies.atprotoSharing,
                publicationStore: publicationStore
            )
            .environment(\.ginnyTheme, theme)
            .preferredColorScheme(theme.mode.colorScheme)
        }
    }

    private var chatSurface: some View {
        ZStack {
            theme.color("background")
                .ignoresSafeArea()

            ZStack(alignment: .bottom) {
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
                                                    artefactStore: artefacts,
                                                    markdownConfig: markdownConfig,
                                                    thinkingMarkdownConfig: thinkingMarkdownConfig
                                                )
                                                .id(item.id)
                                            case .toolActivity(let message, let group):
                                                ChatMessageView(
                                                    message: message,
                                                    toolActivity: group,
                                                    artefactStore: artefacts,
                                                    markdownConfig: markdownConfig,
                                                    thinkingMarkdownConfig: thinkingMarkdownConfig
                                                )
                                                .id(item.id)
                                            }
                                        }

                                        if let activeResponse {
                                            if showsLiveResponse {
                                                if !currentStreamingReasoningText.isEmpty,
                                                   showsLiveThinking {
                                                    LiveThinkingDisclosureView(
                                                        source: activeResponse.thinkingSource,
                                                        markdownConfig: thinkingMarkdownConfig,
                                                        isComplete: !session.isGenerating
                                                    )
                                                    .id("active-thinking")
                                                }
                                                StreamedMarkdownView(
                                                    source: activeResponse.source,
                                                    config: markdownConfig.withTextAnimation(.fastFade)
                                                )
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .id("active-response")
                                            }
                                            if let approval = session.pendingToolApproval {
                                                ToolApprovalView(
                                                    request: approval,
                                                    approve: session.approvePendingTool,
                                                    deny: session.denyPendingTool
                                                )
                                                .id("tool-approval")
                                            }
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

                                        Color.clear
                                            .frame(height: composerReservedHeight)
                                            .id("chat-bottom")
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
                                proxy.scrollTo("chat-bottom", anchor: .bottom)
                            }
                        }
                        .onChange(of: session.conversation.messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("chat-bottom", anchor: .bottom)
                            }
                        }
                    }

                    ChatHeader(
                        title: conversationTitle,
                        onOpenSidebar: { setSidebarPresented(true) },
                        onShare: { showsSharePreview = true }
                    )
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .background {
                        LinearGradient(
                            colors: [
                                theme.color("background").opacity(0.94),
                                theme.color("background").opacity(0.93),
                                theme.color("background").opacity(0.90),
                                theme.color("background").opacity(0.87),
                                theme.color("background").opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .top)
                    }
                    .zIndex(1)
                }
                .frame(maxHeight: .infinity)

                LinearGradient(
                    colors: [
                        theme.color("background").opacity(0),
                        theme.color("background").opacity(0.2),
                        theme.color("background").opacity(0.75),
                        theme.color("background").opacity(0.93),
                        theme.color("background").opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: composerReservedHeight + 32)
                .ignoresSafeArea(edges: .bottom)
                .offset(y: 34)
                .allowsHitTesting(false)
                .zIndex(1)

                ComposerView(
                    draft: $draft,
                    settings: settings,
                    contextStore: contextStore,
                    selectedContextID: $selectedContextID,
                    messages: session.conversation.messages,
                    artefacts: artefacts.artefacts,
                    isGenerating: session.isGenerating,
                    send: send,
                    cancel: cancel,
                    openSettings: { showsSettings = true }
                )
                .zIndex(2)
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

    private var showsLiveResponse: Bool {
        guard session.isGenerating,
              let lastMessage = session.conversation.messages.last,
              lastMessage.role == .assistant
        else {
            return false
        }
        return !lastMessage.blocks.contains { $0.kind == .toolCall }
    }

    private var showsLiveThinking: Bool {
        guard let lastMessage = session.conversation.messages.last,
              lastMessage.role == .assistant
        else {
            return false
        }
        return lastMessage.providerContinuations.contains { $0.kind == "reasoning" }
    }

    private var currentStreamingReasoningText: String {
        guard let lastMessage = session.conversation.messages.last,
              lastMessage.role == .assistant
        else {
            return ""
        }
        return lastMessage.providerContinuations
            .filter { $0.kind == "reasoning" }
            .compactMap { $0.fields["thinking"] ?? $0.fields["text"] }
            .joined()
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

    private func resetLocalData() {
        session.reset()
        history.refresh()
        artefacts.refresh()
        contextStore.refresh()
        publicationStore.removeAll()
        selectedContextID = nil
        activeResponse = nil
        draft = ""
    }

    private func configureSelectedContext() {
        guard let selectedContextID,
              let context = contextStore.contexts.first(where: { $0.id == selectedContextID })
        else {
            session.configure(contextInput: nil)
            return
        }

        session.configure(
            contextInput: contextStore.assemblyInput(
                for: context,
                messages: session.conversation.messages,
                artefacts: artefacts.artefacts
            )
        )
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

    private var thinkingMarkdownConfig: MarkdownRenderConfig {
        let base = markdownConfig
        let muted = theme.color("text.muted")

        return base
            .withParagraphStyle(value: .init(
                textFonts: base.paragraphStyle.textFonts,
                textColor: muted
            ))
            .withBlockQuoteStyle(value: .init(
                textFonts: base.blockQuoteStyle.textFonts,
                textColor: muted
            ))
            .withHeadingStyle(value: .init(
                h1Font: base.headingStyle.h1Font,
                h2Font: base.headingStyle.h2Font,
                h3Font: base.headingStyle.h3Font,
                h4Font: base.headingStyle.h4Font,
                h5Font: base.headingStyle.h5Font,
                h6Font: base.headingStyle.h6Font,
                textColor: muted
            ))
            .withOrderedListStyle(value: .init(
                textFonts: base.orderedListStyle.textFonts,
                textColor: muted
            ))
            .withInlineStyle(value: .init(
                boldTextColor: muted,
                linkTextFont: base.inlineStyle.linkTextFont,
                linkTextColor: muted,
                codeTextFont: base.inlineStyle.codeTextFont,
                codeTextColor: muted,
                codeBackgroundColor: base.inlineStyle.codeBackgroundColor,
                codeUnderlineColor: muted
            ))
            .withThematicBreakColor(value: muted)
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
            await LiveActivityController.shared.start(
                conversationID: session.conversation.id.rawValue.rawValue,
                model: settings.modelText,
                thinkingLevel: settings.thinkingLevel.displayName
            )
            await session.send(prompt)
            artefacts.refresh()
            let completedConversation = session.conversation
            let activityStatus: GinnyLiveActivityAttributes.ContentState.Status
            let activityDetail: String
            switch completedConversation.generationState {
            case .completed:
                activityStatus = .completed
                activityDetail = "Done"
            case .cancelled:
                activityStatus = .cancelled
                activityDetail = "Cancelled"
            case .failed:
                activityStatus = .failed
                activityDetail = session.errorMessage ?? "Generation failed"
            case .idle, .preparing, .streaming:
                activityStatus = .failed
                activityDetail = "Generation ended"
            }
            await LiveActivityController.shared.end(
                status: activityStatus,
                detail: activityDetail
            )
            if [.completed, .cancelled, .failed].contains(completedConversation.generationState) {
                history.save(completedConversation)
                if completedConversation.generationState == .completed {
                    Task { @MainActor in
                        await history.generateTitle(for: completedConversation)
                    }
                }
            }
            response.source.finish()
            response.thinkingSource.finish()
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

enum AssistantContentSegment: Equatable, Identifiable {
    case text(ContentBlock, rendererKind: ContentBlockRendererKind)
    case toolActivity(id: ContentBlockID, group: ToolActivityGroup)
    case artefactReference(id: ContentBlockID, reference: ArtefactReference)

    var id: ContentBlockID {
        switch self {
        case .text(let block, _):
            block.id
        case .toolActivity(let id, _), .artefactReference(let id, _):
            id
        }
    }
}

func assistantContentSegments(
    for message: Message,
    toolActivity: ToolActivityGroup?
) -> [AssistantContentSegment] {
    guard message.role == .assistant else { return [] }

    let results = toolActivity.map { group in
        group.activities.compactMap(\.result) + group.unmatchedResults
    } ?? []
    var segments: [AssistantContentSegment] = []
    let rendererRegistry = ContentBlockRendererRegistry()
    var index = 0

    while index < message.blocks.count {
        let block = message.blocks[index]
        switch block.kind {
        case .text:
            if !block.payload.isEmpty {
                segments.append(
                    .text(
                        block,
                        rendererKind: rendererRegistry.rendererKind(for: block.kind)
                    )
                )
            }
            index += 1
        case .citationGroup:
            if toolActivity == nil, !block.payload.isEmpty {
                segments.append(
                    .text(
                        block,
                        rendererKind: rendererRegistry.rendererKind(for: block.kind)
                    )
                )
            }
            index += 1
        case .markdown, .code, .table, .mermaid, .image, .fileReference, .providerNotice, .unknown:
            if !block.payload.isEmpty || block.kind == .fileReference {
                segments.append(
                    .text(
                        block,
                        rendererKind: rendererRegistry.rendererKind(for: block.kind)
                    )
                )
            }
            index += 1
        case .toolCall:
            let startIndex = index
            while index < message.blocks.count, message.blocks[index].kind == .toolCall {
                index += 1
            }
            let calls = Array(message.blocks[startIndex..<index])
            let callIDs = Set(calls.compactMap { $0.attributes["callID"] })
            let relatedResults = results.filter {
                guard let callID = $0.attributes["callID"] else { return false }
                return callIDs.contains(callID)
            }
            segments.append(
                .toolActivity(
                    id: calls[0].id,
                    group: ToolActivityGroup(calls: calls, results: relatedResults)
                )
            )
        case .artefactReference:
            if let reference = ArtefactReference(block: block) {
                segments.append(.artefactReference(id: block.id, reference: reference))
            }
            index += 1
        case .toolResult:
            index += 1
        }
    }

    return segments
}

@MainActor
private struct ChatHeader: View {
    let title: String
    let onOpenSidebar: () -> Void
    let onShare: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenSidebar) {
                HeaderIconButton(systemImage: "text.menu")
            }
            .accessibilityLabel("Open session history")
            .accessibilityIdentifier("header.sessionHistory")

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .contentTransition(.interpolate)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.22),
                    value: title
                )

            Spacer(minLength: 8)

            Button(action: onShare) {
                HeaderIconButton(systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share conversation")
            .accessibilityIdentifier("header.shareConversation")
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

@MainActor
private struct ConversationSharePreviewSheet: View {
    let conversation: Conversation
    let artefacts: [Artefact]
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
                    Text(publication == nil ? "Share conversation" : "Update public snapshot")
                        .font(.title2.weight(.semibold))
                    Text(conversation.title ?? "Untitled conversation")
                        .font(.headline)
                    Text("This creates a public atproto record. You choose when to publish and update it.")
                        .font(.subheadline)
                        .foregroundStyle(theme.color("text.muted"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Public snapshot", systemImage: "globe")
                        .font(.headline)
                    Text("Visible messages and referenced artefacts are included. Hidden reasoning and raw tool payloads stay local.")
                        .font(.footnote)
                        .foregroundStyle(theme.color("text.muted"))
                }
                .padding(16)
                .background(theme.color("card"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer()

                Button(action: publish) {
                    HStack {
                        if isWorking { ProgressView().tint(theme.color("primary_foreground")) }
                        Text(publication == nil ? "Publish" : "Update record")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .shimmering(active: isWorking)
                .disabled(isWorking || conversation.messages.isEmpty)

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
                "Couldn’t share conversation",
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
                var publishedArtefactReferences: [RinaArtefactReference] = []
                for reference in referencedArtefactReferences {
                    guard let artefact = artefacts.first(where: { $0.id == reference.artefactID }) else {
                        throw AtprotoSharingError.missingReferencedArtefact(reference.artefactID)
                    }
                    let subjectID = publicationSubjectID(for: reference)
                    let existingPublication = publicationStore.publications.first {
                        $0.collection == AtprotoRecordCollection.artefact
                            && $0.subjectID == subjectID
                    }
                    let artefactSnapshot = try AtprotoSnapshotBuilder.artefact(
                        artefact,
                        revisionID: reference.revisionID
                    )
                    let publishedArtefact = try await sharingService.publish(
                        artefactSnapshot,
                        publication: existingPublication,
                        subjectID: subjectID
                    )
                    publicationStore.save(publishedArtefact)
                    publishedArtefactReferences.append(
                        RinaArtefactReference(
                            id: reference.artefactID.rawValue.rawValue,
                            revisionID: reference.revisionID.rawValue.rawValue,
                            uri: publishedArtefact.uri
                        )
                    )
                }

                let snapshot = AtprotoSnapshotBuilder.conversation(
                    conversation,
                    artefactReferences: publishedArtefactReferences
                )
                let published = try await sharingService.publish(
                    snapshot,
                    publication: publication,
                    subjectID: conversation.id.rawValue.rawValue
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
                let childSubjectIDs = Set(referencedArtefactReferences.map(publicationSubjectID))
                let childPublications = publicationStore.publications.filter {
                    $0.collection == AtprotoRecordCollection.artefact
                        && childSubjectIDs.contains($0.subjectID ?? "")
                }
                for childPublication in childPublications {
                    try await sharingService.delete(childPublication)
                    publicationStore.remove(
                        collection: childPublication.collection,
                        rkey: childPublication.rkey
                    )
                }
                try await sharingService.delete(publication)
                publicationStore.remove(collection: publication.collection, rkey: publication.rkey)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private var referencedArtefactReferences: [ArtefactReference] {
        var seen = Set<String>()
        return conversation.messages
            .flatMap(\.blocks)
            .compactMap(ArtefactReference.init(block:))
            .filter { reference in
                let key = publicationSubjectID(for: reference)
                return seen.insert(key).inserted
            }
    }

    private func publicationSubjectID(for reference: ArtefactReference) -> String {
        "\(reference.artefactID.rawValue.rawValue):\(reference.revisionID.rawValue.rawValue)"
    }
}

@MainActor
private struct SessionSidebar: View {
    @ObservedObject var history: SessionHistoryStore
    @ObservedObject var themeStore: ThemeStore
    let currentConversationID: ConversationID
    let onSelect: (Conversation) -> Void
    let onNewConversation: () -> Void
    let onSearch: () -> Void
    let onWorkspace: () -> Void
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

            Button(action: onSearch) {
                Label("Search workspace", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .foregroundStyle(theme.color("text.body"))
            .accessibilityLabel("Search workspace")
            .accessibilityIdentifier("sidebar.searchWorkspace")

            Button(action: onWorkspace) {
                Label("Artefacts & skills", systemImage: "square.stack.3d.up")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .foregroundStyle(theme.color("text.body"))
            .accessibilityLabel("Open artefacts and skills")

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
            .accessibilityIdentifier("sidebar.settings")
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
    @ObservedObject var contextStore: ContextStore
    @Binding var selectedContextID: ContextID?
    let messages: [Message]
    let artefacts: [Artefact]
    let isGenerating: Bool
    let send: () -> Void
    let cancel: () -> Void
    let openSettings: () -> Void
    @Environment(\.ginnyTheme) private var theme
    @FocusState private var isInputFocused: Bool

    private var canSubmit: Bool {
        isGenerating || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Start a message", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(submit)

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

                ContextPickerButton(
                    store: contextStore,
                    selectedContextID: $selectedContextID,
                    messages: messages,
                    artefacts: artefacts
                )

                Spacer(minLength: 0)

                Button(action: isGenerating ? cancel : submit) {
                    Image(systemName: isGenerating ? "stop" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(theme.color("primary_foreground"))
                        .background(theme.color("primary"), in: Circle())
                }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.38)
                .accessibilityLabel(isGenerating ? "Stop generating" : "Send message")
                .accessibilityIdentifier("composer.send")
            }
        }
        .padding(12)
        .frame(minHeight: 100, alignment: .top)
        .ginnyGlass(
            RoundedRectangle(cornerRadius: 28, style: .continuous),
            prominence: .elevated
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func submit() {
        isInputFocused = false
        send()
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
        .accessibilityIdentifier("composer.modelPicker")
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
                        HStack(spacing: 8) {
                            ThinkingIndicator(isAnimating: true)
                            Text("Loading models…")
                        }
                        .foregroundStyle(theme.color("text.muted"))
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
                            ThinkingIndicator(isAnimating: true)
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
    let thinkingSource = ChatResponseSource()
}

private struct ChatMessageView: View {
    let message: Message
    let toolActivity: ToolActivityGroup?
    @ObservedObject var artefactStore: ArtefactStore
    let markdownConfig: MarkdownRenderConfig
    let thinkingMarkdownConfig: MarkdownRenderConfig
    @Environment(\.ginnyTheme) private var theme

    init(
        message: Message,
        toolActivity: ToolActivityGroup? = nil,
        artefactStore: ArtefactStore,
        markdownConfig: MarkdownRenderConfig,
        thinkingMarkdownConfig: MarkdownRenderConfig
    ) {
        self.message = message
        self.toolActivity = toolActivity
        self.artefactStore = artefactStore
        self.markdownConfig = markdownConfig
        self.thinkingMarkdownConfig = thinkingMarkdownConfig
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
                    if hasReasoning {
                        ThinkingDisclosureView(
                            snapshot: reasoningText,
                            isRedacted: isRedactedReasoning,
                            markdownConfig: thinkingMarkdownConfig
                        )
                    }
                    ForEach(assistantContentSegments(for: message, toolActivity: toolActivity)) { segment in
                        switch segment {
                        case .text(let block, let rendererKind):
                            contentView(block, rendererKind: rendererKind)
                        case .toolActivity(_, let group):
                            ToolActivityGroupView(
                                group: group,
                                citations: citationItems(for: group)
                            )
                        case .artefactReference(_, let reference):
                            ArtefactReferenceView(
                                reference: reference,
                                store: artefactStore,
                                markdownConfig: markdownConfig
                            )
                        }
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

    private func citationItems(for group: ToolActivityGroup) -> [Citation] {
        let citationBlocks = message.blocks.filter { $0.kind == .citationGroup }
        let callIDs = Set(group.activities.compactMap { $0.call.attributes["callID"] })
        let hasCallIDAssociations = citationBlocks.contains {
            $0.attributes["callID"] != nil
        }
        let matchingBlocks = citationBlocks.filter { block in
            guard let blockCallID = block.attributes["callID"] else {
                return !hasCallIDAssociations
            }
            return callIDs.contains(blockCallID)
        }

        return matchingBlocks.flatMap { block in
                guard let data = block.payload.data(using: .utf8) else { return [Citation]() }
                return (try? JSONDecoder().decode([Citation].self, from: data)) ?? []
        }
    }

    @ViewBuilder
    private func contentView(
        _ block: ContentBlock,
        rendererKind: ContentBlockRendererKind
    ) -> some View {
        switch rendererKind {
        case .markdown, .table:
            MarkdownView(text: block.payload, config: markdownConfig)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            CodeBlockView(
                source: block.payload,
                language: block.attributes["language"]
            )
        case .mermaid:
            MermaidBlockView(source: block.payload)
        case .image:
            ImageBlockView(
                reference: block.payload,
                alt: block.attributes["alt"]
            )
        case .fileReference:
            FileReferenceBlockView(displayName: block.attributes["displayName"])
        case .citationGroup:
            CitationGroupView(payload: block.payload)
        case .providerNotice:
            ProviderNoticeView(text: block.payload)
        case .unsupported:
            Text(block.payload)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolCall, .toolResult, .artefactReference:
            EmptyView()
        }
    }

    private var toolResults: [ContentBlock] {
        message.blocks.filter { $0.kind == .toolResult }
    }

    private var hasReasoning: Bool {
        message.providerContinuations.contains { $0.kind == "reasoning" }
    }

    private var reasoningText: String {
        message.providerContinuations
            .filter { $0.kind == "reasoning" }
            .compactMap { $0.fields["thinking"] ?? $0.fields["text"] }
            .joined()
    }

    private var isRedactedReasoning: Bool {
        message.providerContinuations.contains {
            $0.kind == "reasoning"
                && $0.fields["data"] != nil
                && $0.fields["thinking"] == nil
                && $0.fields["text"] == nil
        }
    }
}

private struct CodeBlockView: View {
    let source: String
    let language: String?
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.color("text.muted"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(source)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            theme.color("card").opacity(0.35),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.map { "\($0) code" } ?? "Code")
    }
}

private struct MermaidBlockView: View {
    let source: String
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Diagram", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.color("text.muted"))
            Text(source)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            theme.color("card").opacity(0.25),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mermaid diagram")
    }
}

private struct ImageBlockView: View {
    let reference: String
    let alt: String?

    var body: some View {
        if let url = URL(string: reference), url.scheme != nil {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 100)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                case .failure:
                    Label("Image unavailable", systemImage: "photo")
                        .frame(maxWidth: .infinity, minHeight: 100)
                @unknown default:
                    EmptyView()
                }
            }
            .accessibilityLabel(alt ?? "Image")
        } else {
            Label(alt ?? "Image reference", systemImage: "photo")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FileReferenceBlockView: View {
    let displayName: String?

    var body: some View {
        Label(
            displayName ?? "Attached file",
            systemImage: "doc"
        )
        .font(.subheadline)
    }
}

private struct ProviderNoticeView: View {
    let text: String
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(theme.color("text.muted"))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ArtefactReferenceView: View {
    let reference: ArtefactReference
    @ObservedObject var store: ArtefactStore
    let markdownConfig: MarkdownRenderConfig
    @Environment(\.ginnyTheme) private var theme
    @State private var inlineHeight: CGFloat = 180
    @State private var approvedNetworkOrigins: [String] = []
    @State private var pendingNetworkOrigin: String?
    @AppStorage(ArtefactPreferences.allowAllNetworkRequestsKey) private var allowAllNetworkRequests = false

    var body: some View {
        if let artefact = store.artefacts.first(where: { $0.id == reference.artefactID }),
           let revision = artefact.revision(id: reference.revisionID) {
            if reference.presentation == .inline {
                if artefact.kind == .web || artefact.kind == .inlineWeb {
                    let declaredNetworkOrigins = ArtefactNetworkPolicy(metadata: revision.metadata).origins
                    let networkOrigins = Array(Set(declaredNetworkOrigins + approvedNetworkOrigins)).sorted()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(artefact.title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(2)
                            .accessibilityAddTraits(.isHeader)

                        WebArtefactPreview(
                            html: revision.renderedContent ?? revision.source,
                            isInline: true,
                            networkOrigins: networkOrigins,
                            contentHeight: $inlineHeight,
                            allowAllNetworkRequests: allowAllNetworkRequests,
                            onNetworkOriginRequest: { origin in
                                guard !networkOrigins.contains(origin), pendingNetworkOrigin == nil else { return }
                                pendingNetworkOrigin = origin
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: min(inlineHeight, WebArtefactPreview.maxInlineHeight))
                    }
                    .alert(
                        "Allow network access?",
                        isPresented: Binding(
                            get: { pendingNetworkOrigin != nil },
                            set: { isPresented in
                                if !isPresented { pendingNetworkOrigin = nil }
                            }
                        )
                    ) {
                        Button("Allow") {
                            if let origin = pendingNetworkOrigin,
                               !approvedNetworkOrigins.contains(origin) {
                                approvedNetworkOrigins.append(origin)
                            }
                            pendingNetworkOrigin = nil
                        }
                        Button("Don’t Allow", role: .cancel) {
                            pendingNetworkOrigin = nil
                        }
                    } message: {
                        Text("This artefact wants to connect to \(pendingNetworkOrigin ?? "a new site").")
                    }
                } else {
                    InlineArtefactContentView(
                        artefact: artefact,
                        revision: revision,
                        markdownConfig: markdownConfig
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: artefact.kind == .inlineWeb ? "rectangle.on.rectangle" : "doc.text")
                        Text(artefact.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(artefact.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(theme.color("text.muted"))
                    }

                    Text(revision.source)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.color("text.muted"))
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(
                    theme.color("card").opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        } else {
            Label("Artefact unavailable", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(theme.color("text.muted"))
        }
    }
}

private struct InlineArtefactContentView: View {
    let artefact: Artefact
    let revision: ArtefactRevision
    let markdownConfig: MarkdownRenderConfig
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(artefact.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
            }
            .accessibilityAddTraits(.isHeader)

            Divider()

            switch artefact.kind {
            case .document:
                MarkdownView(
                    text: revision.renderedContent ?? revision.source,
                    config: markdownConfig
                )
            case .code:
                ScrollView(.horizontal) {
                    Text(revision.source)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            case .web, .inlineWeb:
                EmptyView()
            }
        }
        .padding(14)
        .background(
            theme.color("card").opacity(0.22),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var systemImage: String {
        switch artefact.kind {
        case .document: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .web: "globe"
        case .inlineWeb: "rectangle.on.rectangle"
        }
    }
}

private struct ProviderSettingsView: View {
    @ObservedObject var settings: ProviderSettings
    let authService: AtprotoAuthService
    @ObservedObject var themeStore: ThemeStore
    let dataResetter: LocalDataResetter
    let onDataReset: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ginnyTheme) private var theme
    @State private var showsClearDataConfirmation = false
    @State private var isClearingData = false
    @State private var dataErrorMessage: String?

    var body: some View {
        List {
            Section("Connection") {
                NavigationLink {
                    ProviderConfigurationSettingsView(settings: settings)
                } label: {
                    SettingsNavigationRow(
                        title: "Provider and models",
                        summary: providerSummary,
                        systemImage: "square.3.layers.3d"
                    )
                }

                NavigationLink {
                    AtprotoAccountSettingsView(authService: authService)
                } label: {
                    SettingsNavigationRow(
                        title: "atproto account",
                        summary: "Sign in for sharing and sync",
                        systemImage: "person.crop.circle"
                    )
                }
            }

            Section("Workspace") {
                NavigationLink {
                    ArtefactSettingsView(settings: settings)
                } label: {
                    SettingsNavigationRow(
                        title: "Artefacts and web",
                        summary: artefactSummary,
                        systemImage: "square.stack.3d.up"
                    )
                }

                NavigationLink {
                    WebSearchSettingsView(settings: settings)
                } label: {
                    SettingsNavigationRow(
                        title: "Web search",
                        summary: settings.webSearchProvider.displayName,
                        systemImage: "globe"
                    )
                }

                NavigationLink {
                    AppearanceSettingsView(themeStore: themeStore)
                } label: {
                    SettingsNavigationRow(
                        title: "Appearance",
                        summary: themeStore.displayName(for: themeStore.selectedThemeID),
                        systemImage: "paintpalette"
                    )
                }
            }

            Section("Data") {
                Button(role: .destructive) {
                    showsClearDataConfirmation = true
                } label: {
                    Label("Clear local data", systemImage: "trash")
                }
                .disabled(isClearingData)

                Text("Deletes sessions, artefacts, imported sources, contexts, search data, and local attachments. Provider credentials and your atproto sign-in stay in place.")
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
            }

            Section {
                Text("Credentials stay in the system Keychain. Remote endpoints require HTTPS; localhost HTTP is allowed for local development.")
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if settings.save() {
                        dismiss()
                    }
                }
            }
        }
        .alert("Clear local data?", isPresented: $showsClearDataConfirmation) {
            Button("Clear local data", role: .destructive) {
                clearLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all locally stored workspace content. It cannot be undone.")
        }
        .alert(
            "Could not clear local data",
            isPresented: Binding(
                get: { dataErrorMessage != nil },
                set: { if !$0 { dataErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dataErrorMessage ?? "Try again.")
        }
        .task {
            await settings.refreshModels()
        }
    }

    private func clearLocalData() {
        isClearingData = true
        Task { @MainActor in
            do {
                try await dataResetter.reset()
                isClearingData = false
                onDataReset()
                dismiss()
            } catch {
                isClearingData = false
                dataErrorMessage = error.localizedDescription
            }
        }
    }

    private var providerSummary: String {
        let model = settings.modelText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? settings.provider.displayName : "\(settings.provider.displayName) · \(model)"
    }

    private var artefactSummary: String {
        if settings.allowAllArtefactWebRequests && settings.autoApproveArtefactWrites {
            return "Relaxed web and write approvals"
        }
        if settings.allowAllArtefactWebRequests {
            return "Relaxed web approvals"
        }
        if settings.autoApproveArtefactWrites {
            return "Relaxed write approvals"
        }
        return "Approval safeguards on"
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let summary: String
    let systemImage: String
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.color("primary"))
                .frame(width: 26)
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderConfigurationSettingsView: View {
    @ObservedObject var settings: ProviderSettings
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Form {
            Section("Service") {
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
            }

            Section("Model") {
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
                    TextField("Model identifier", text: $settings.modelText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if settings.provider == .umans {
                    HStack {
                        if settings.isLoadingModels {
                            ThinkingIndicator(isAnimating: true)
                        }
                        Button("Refresh models") {
                            Task { await settings.refreshModels() }
                        }
                        .disabled(settings.isLoadingModels)
                    }
                }
            }

            Section("Credential") {
                SecureField("API key", text: $settings.credentialText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("The key is stored in the system Keychain and is only attached when a request is sent.")
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
            }

            if let validationMessage = settings.validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(theme.color("text.error"))
                }
            }

            if let catalogMessage = settings.catalogMessage {
                Section {
                    Text(catalogMessage)
                        .foregroundStyle(theme.color("text.error"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
        .navigationTitle("Provider and models")
    }
}

private struct ArtefactSettingsView: View {
    @ObservedObject var settings: ProviderSettings
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Form {
            Section("Permissions") {
                Toggle("Allow all HTTPS requests", isOn: $settings.allowAllArtefactWebRequests)
                Toggle("Auto-approve artefact writes", isOn: $settings.autoApproveArtefactWrites)
            }

            Section {
                Text("These options relax artefact-only safeguards. HTTPS remains required, and local or private addresses remain blocked.")
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
        .navigationTitle("Artefacts and web")
    }
}

private struct WebSearchSettingsView: View {
    @ObservedObject var settings: ProviderSettings
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Form {
            Section("Search service") {
                Picker("Provider", selection: $settings.webSearchProvider) {
                    ForEach(WebSearchProviderID.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.webSearchProvider) { _, provider in
                    settings.selectWebSearchProvider(provider)
                }

                TextField("Base URL", text: $settings.webSearchEndpointText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                SecureField("API key", text: $settings.webSearchCredentialText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Text("Search results include citation metadata. Use an HTTPS endpoint for the selected provider.")
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
        .navigationTitle("Web search")
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var themeStore: ThemeStore
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        Form {
            Section("Theme") {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { themeStore.selectedThemeID },
                        set: { themeStore.select(themeID: $0) }
                    )
                ) {
                    ForEach(themeStore.availableThemeIDs, id: \.self) { themeID in
                        Text(themeStore.displayName(for: themeID)).tag(themeID)
                    }
                }
            }

            Section {
                Text("Themes change the app chrome and artefact surfaces while preserving the same content hierarchy.")
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
        .navigationTitle("Appearance")
    }
}

private enum AtprotoAuthMethod: String {
    case oauth
    case appPassword
}

private struct AtprotoAccountSettingsView: View {
    let authService: AtprotoAuthService
    @Environment(\.ginnyTheme) private var theme
    @State private var state: AtprotoAuthState = .signedOut
    @State private var authMethod: AtprotoAuthMethod = .oauth
    @State private var handle = ""
    @State private var appPassword = ""
    @State private var pdsURL = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Account") {
                switch state {
                case .signedOut:
                    Picker("Sign-in method", selection: $authMethod) {
                        Text("OAuth").tag(AtprotoAuthMethod.oauth)
                        Text("App password").tag(AtprotoAuthMethod.appPassword)
                    }
                    .pickerStyle(.segmented)

                    if authMethod == .oauth {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 28))
                                    .foregroundStyle(theme.color("primary"))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Sign in with atproto")
                                        .font(.headline)
                                    Text("Use your account provider to continue.")
                                        .font(.subheadline)
                                        .foregroundStyle(theme.color("text.muted"))
                                }
                            }

                            TextField("Handle or DID", text: $handle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Text("Ginny will open your provider’s website. Your password stays there, and you’ll return here when you’re done.")
                                .font(.footnote)
                                .foregroundStyle(theme.color("text.muted"))

                            Button {
                                signInWithOAuth()
                            } label: {
                                Label(isSigningIn ? "Opening sign-in…" : "Continue in browser", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isSigningIn)
                        }
                        .padding(.vertical, 4)
                    } else {
                        TextField("Handle or DID", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("PDS URL override", text: $pdsURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        Text("Leave blank to resolve the PDS from the handle.")
                            .font(.footnote)
                            .foregroundStyle(theme.color("text.muted"))

                        SecureField("App password", text: $appPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button(isSigningIn ? "Signing in…" : "Sign in") {
                            signIn()
                        }
                        .disabled(isSigningIn)

                        Text("The app password is stored in the system Keychain.")
                            .font(.footnote)
                            .foregroundStyle(theme.color("text.muted"))
                    }
                case .signedIn(let account):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.handle)
                            .font(.headline)
                        Text(account.did)
                            .font(.footnote)
                            .foregroundStyle(theme.color("text.muted"))
                        Text(account.pdsURL)
                            .font(.footnote)
                            .foregroundStyle(theme.color("text.muted"))
                    }

                    Button("Sign out", role: .destructive) {
                        Task {
                            await authService.signOut()
                            state = .signedOut
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.color("text.error"))
                }
            }
        }
        .task {
            state = await authService.restore()
        }
        .scrollContentBackground(.hidden)
        .background(theme.color("background"))
        .navigationTitle("atproto account")
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                let account = try await authService.signIn(
                    handle: handle,
                    appPassword: appPassword,
                    pdsURL: pdsURL
                )
                state = .signedIn(account)
                appPassword = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    private func signInWithOAuth() {
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                let account = try await authService.signInWithOAuth(identifier: handle)
                state = .signedIn(account)
                appPassword = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
