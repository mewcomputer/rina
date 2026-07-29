import Combine
import Foundation

@MainActor
final class ChatSession: ObservableObject {
    @Published private(set) var conversation: Conversation
    @Published private(set) var streamingText = ""
    @Published private(set) var streamingReasoningText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var persistenceError: String?
    @Published private(set) var pendingToolApproval: ToolApprovalRequest?

    private var provider: (any ProviderAdapter)?
    private var activeGenerationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?
    private var toolRegistry: ToolRegistry
    private let persistence: ((Conversation) throws -> Void)?
    private var toolApprovalContinuation: CheckedContinuation<Bool, Never>?
    private var responseFinishReason: String? = nil
    private var autoApproveArtefactWrites = false

    init(
        provider: (any ProviderAdapter)? = nil,
        conversation: Conversation = Conversation(),
        toolRegistry: ToolRegistry = ToolRegistry(),
        persistence: ((Conversation) throws -> Void)? = nil
    ) {
        self.provider = provider
        self.conversation = conversation
        self.toolRegistry = toolRegistry
        self.persistence = persistence
    }

    func configure(provider: any ProviderAdapter) {
        self.provider = provider
    }

    func configure(skillCatalog: SkillCatalog) {
        toolRegistry.updateSkillCatalog(skillCatalog)
    }

    func configure(autoApproveArtefactWrites: Bool) {
        self.autoApproveArtefactWrites = autoApproveArtefactWrites
    }

    func load(conversation: Conversation) {
        guard !isGenerating else { return }
        self.conversation = conversation
        streamingText = ""
        streamingReasoningText = ""
        errorMessage = nil
        persistenceError = nil
        pendingToolApproval = nil
        responseFinishReason = nil
    }

    func reset() {
        load(conversation: Conversation())
    }

    func attachArtefact(_ artefact: Artefact, to messageID: MessageID) {
        guard var message = conversation.messages.first(where: { $0.id == messageID }),
              !message.blocks.contains(where: {
                  $0.kind == .artefactReference
                      && $0.attributes["artefactID"] == artefact.id.rawValue.uuidString
                      && $0.attributes["revisionID"] == artefact.currentRevisionID?.rawValue.uuidString
              }),
              let revisionID = artefact.currentRevisionID
        else {
            return
        }

        let presentation: ArtefactReferencePresentation = artefact.kind == .inlineWeb
            ? .inline
            : .card
        message.blocks.append(
            .artefactReference(
                artefactID: artefact.id,
                revisionID: revisionID,
                presentation: presentation
            )
        )
        do {
            try conversation.updateMessage(message)
            persistConversation()
        } catch {
            persistenceError = "Couldn’t attach this artefact to the conversation."
        }
    }

    var isGenerating: Bool {
        switch conversation.generationState {
        case .preparing, .streaming:
            true
        case .idle, .completed, .cancelled, .failed:
            false
        }
    }

    func send(_ prompt: String) async {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        let generationID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSend(prompt)
        }
        activeGenerationID = generationID
        activeGenerationTask = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        if activeGenerationID == generationID {
            activeGenerationID = nil
            activeGenerationTask = nil
        }
    }

    func cancel() {
        guard isGenerating else { return }

        activeGenerationTask?.cancel()
        denyPendingToolApproval()
        try? conversation.cancelGeneration()
        persistConversation()
    }

    func approvePendingTool() {
        toolApprovalContinuation?.resume(returning: true)
        toolApprovalContinuation = nil
        pendingToolApproval = nil
    }

    func denyPendingTool() {
        denyPendingToolApproval()
    }

    private func performSend(_ prompt: String) async {

        errorMessage = nil
        persistenceError = nil
        streamingText = ""
        streamingReasoningText = ""

        do {
            guard let provider else {
                errorMessage = "Configure a provider before sending a message."
                return
            }

            try conversation.beginGeneration()
            try conversation.appendMessage(.user(prompt))
            try conversation.appendMessage(
                Message(
                    role: .assistant,
                    blocks: [.text("", isComplete: false)]
                )
            )
            persistConversation()

            while true {
                responseFinishReason = nil
                let request = makeRequest()
                for try await event in provider.stream(for: request) {
                    try handle(event: event)
                    persistConversation()
                }

                guard conversation.generationState == .streaming else { return }
                let pendingToolCalls = conversation.messages.last?.blocks.filter {
                    $0.kind == .toolCall
                } ?? []
                if !pendingToolCalls.isEmpty,
                   !Self.isToolCallFinishReason(responseFinishReason)
                {
                    errorMessage = "The provider ended before completing a tool call."
                    try conversation.failGeneration()
                    persistConversation()
                    return
                }
                let toolCalls = completedToolCalls(
                    in: conversation.messages.last,
                    finishReason: responseFinishReason
                )
                if toolCalls.isEmpty {
                    try finishGeneration()
                    return
                }

                try finalizeAssistantForToolCalls()
                try await execute(toolCalls)
                try conversation.appendMessage(
                    Message(
                        role: .assistant,
                        blocks: [.text("", isComplete: false)]
                    )
                )
                streamingText = ""
                persistConversation()
            }
        } catch is CancellationError {
            denyPendingToolApproval()
            try? conversation.cancelGeneration()
            persistConversation()
        } catch {
            denyPendingToolApproval()
            errorMessage = message(for: error)
            try? conversation.failGeneration()
            persistConversation()
        }
    }

    private func handle(event: ProviderStreamEvent) throws {
        switch event {
        case .responseStarted:
            guard conversation.generationState == .preparing else { return }
            try conversation.beginStreaming()
        case .textDelta(let delta):
            if conversation.generationState == .preparing {
                try conversation.beginStreaming()
            }
            guard conversation.generationState == .streaming else { return }
            guard var assistant = conversation.messages.last,
                  assistant.role == .assistant
            else {
                return
            }

            streamingText.append(delta)
            if let textIndex = assistant.blocks.firstIndex(where: { $0.kind == .text }) {
                assistant.blocks[textIndex].payload = streamingText
                assistant.blocks[textIndex].isComplete = false
            } else {
                assistant.blocks.insert(.text(streamingText, isComplete: false), at: 0)
            }
            try conversation.updateMessage(assistant)
        case .continuationDelta(let delta):
            if conversation.generationState == .preparing {
                try conversation.beginStreaming()
            }
            guard conversation.generationState == .streaming,
                  var assistant = conversation.messages.last,
                  assistant.role == .assistant
            else {
                return
            }

            if let index = assistant.providerContinuations.firstIndex(where: {
                $0.provider == delta.provider
                    && $0.id == delta.id
                    && $0.kind == delta.kind
            }) {
                switch delta.operation {
                case .append:
                    assistant.providerContinuations[index].fields[delta.field, default: ""] += delta.value
                case .replace:
                    assistant.providerContinuations[index].fields[delta.field] = delta.value
                }
            } else {
                assistant.providerContinuations.append(
                    ProviderContinuation(
                        provider: delta.provider,
                        id: delta.id,
                        kind: delta.kind,
                        fields: [delta.field: delta.value]
                    )
                )
            }
            if delta.field == "thinking" || delta.field == "text" {
                switch delta.operation {
                case .append:
                    streamingReasoningText += delta.value
                case .replace:
                    streamingReasoningText = delta.value
                }
            }
            try conversation.updateMessage(assistant)
        case .toolCallDelta(let delta):
            if conversation.generationState == .preparing {
                try conversation.beginStreaming()
            }
            guard conversation.generationState == .streaming,
                  var assistant = conversation.messages.last,
                  assistant.role == .assistant
            else {
                return
            }

            if let index = assistant.blocks.firstIndex(where: {
                $0.kind == .toolCall && $0.attributes["callID"] == delta.id
            }) {
                if let name = delta.name {
                    assistant.blocks[index].attributes["name"] = name
                }
                if let arguments = delta.arguments {
                    assistant.blocks[index].payload += arguments
                }
            } else {
                assistant.blocks.append(
                    .toolCall(
                        callID: delta.id,
                        name: delta.name ?? "",
                        arguments: delta.arguments ?? ""
                    )
                )
            }
            try conversation.updateMessage(assistant)
        case .finish(let reason):
            responseFinishReason = reason
        case .responseEnded:
            break
        }
    }

    private func makeRequest() -> ProviderRequest {
        ProviderRequest(
            messages: [
                .system(AgentInstructions.artefactCapabilities)
            ] + conversation.messages.dropLast().map { message in
                let toolCalls = message.blocks.compactMap { block -> ProviderToolCall? in
                    guard block.kind == .toolCall,
                          let id = block.attributes["callID"],
                          let name = block.attributes["name"]
                    else {
                        return nil
                    }
                    return ProviderToolCall(
                        id: id,
                        name: name,
                        arguments: block.payload,
                        isComplete: block.isComplete
                    )
                }
                let toolCallID = message.blocks.first(where: { $0.kind == .toolResult })?
                    .attributes["callID"]
                let toolResultIsError = message.blocks.first(where: { $0.kind == .toolResult })?
                    .attributes["isError"] == "true"
                return ProviderMessage(
                    role: ProviderMessageRole(rawValue: message.role.rawValue) ?? .user,
                    content: message.blocks
                        .filter { $0.kind == .text || $0.kind == .toolResult }
                        .map(\.payload)
                        .joined(),
                    continuations: message.providerContinuations,
                    toolCalls: toolCalls,
                    toolCallID: toolCallID,
                    toolResultIsError: toolCallID == nil ? nil : toolResultIsError
                )
            },
            tools: provider?.supportsTools == true ? toolRegistry.definitions : []
        )
    }

    private func completedToolCalls(
        in message: Message?,
        finishReason: String?
    ) -> [ContentBlock] {
        guard Self.isToolCallFinishReason(finishReason) else { return [] }
        return message?.blocks.filter { $0.kind == .toolCall } ?? []
    }

    private static func isToolCallFinishReason(_ reason: String?) -> Bool {
        reason == "tool_calls" || reason == "tool_use"
    }

    private func finalizeAssistantForToolCalls() throws {
        guard var assistant = conversation.messages.last,
              assistant.role == .assistant
        else {
            return
        }

        for index in assistant.blocks.indices where assistant.blocks[index].kind == .toolCall {
            assistant.blocks[index].isComplete = true
        }
        if let index = assistant.blocks.firstIndex(where: { $0.kind == .text }) {
            assistant.blocks[index].isComplete = true
        }
        try conversation.updateMessage(assistant)
    }

    private func execute(_ calls: [ContentBlock]) async throws {
        let assistantMessageID = conversation.messages.last?.id

        for call in calls {
            guard let callID = call.attributes["callID"],
                  let name = call.attributes["name"]
            else {
                continue
            }

            do {
                let approvalState: ToolApprovalState
                let approvalRequirement = autoApproveArtefactWrites
                    && (name == "create_artefact" || name == "update_artefact")
                    ? .automatic
                    : toolRegistry.approvalRequirement(for: name, arguments: call.payload)
                switch approvalRequirement {
                case .automatic:
                    approvalState = .automatic
                case .requiresApproval:
                    guard await requestToolApproval(for: call) else {
                        try conversation.appendMessage(
                            Message(
                                role: .tool,
                                blocks: [
                                    .toolResult(
                                        callID: callID,
                                        result: "Tool call denied by the user.",
                                        isError: true,
                                        approvalState: .denied
                                    )
                                ]
                            )
                        )
                        continue
                    }
                    approvalState = .approved
                case nil:
                    throw ToolExecutionError.unknownTool(name)
                }

                let result = try await toolRegistry.execute(name: name, arguments: call.payload)
                try appendToolResult(
                    callID: callID,
                    result: result,
                    approvalState: approvalState,
                    to: assistantMessageID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try appendToolResult(
                    callID: callID,
                    result: "Tool error: \(error.localizedDescription)",
                    isError: true,
                    approvalState: nil,
                    to: assistantMessageID
                )
            }
        }
    }

    private func appendToolResult(
        callID: String,
        result: String,
        isError: Bool = false,
        approvalState: ToolApprovalState?,
        to assistantMessageID: MessageID?
    ) throws {
        try conversation.appendMessage(
            Message(
                role: .tool,
                blocks: [
                    .toolResult(
                        callID: callID,
                        result: result,
                        isError: isError,
                        approvalState: approvalState
                    )
                ]
            )
        )

        guard !isError,
              let assistantMessageID,
              let details = try? JSONDecoder().decode(
                  ArtefactToolDetails.self,
                  from: Data(result.utf8)
              ),
              details.displayImmediately || details.kind == .inlineWeb,
              let artefactUUID = UUID(uuidString: details.id),
              let revisionUUID = UUID(uuidString: details.revisionID),
              var assistant = conversation.messages.first(where: {
                  $0.id == assistantMessageID && $0.role == .assistant
              })
        else {
            return
        }

        let artefactID = ArtefactID(rawValue: artefactUUID)
        let revisionID = RevisionID(rawValue: revisionUUID)
        guard !assistant.blocks.contains(where: {
            $0.kind == .artefactReference
                && $0.attributes["artefactID"] == artefactID.rawValue.uuidString
                && $0.attributes["revisionID"] == revisionID.rawValue.uuidString
        })
        else {
            return
        }

        assistant.blocks.append(
            .artefactReference(
                artefactID: artefactID,
                revisionID: revisionID,
                presentation: .inline
            )
        )
        try conversation.updateMessage(assistant)
    }

    private func finishGeneration() throws {
        guard conversation.generationState == .streaming else { return }

        guard var assistant = conversation.messages.last,
              assistant.role == .assistant
        else {
            return
        }

        if let index = assistant.blocks.firstIndex(where: { $0.kind == .text }) {
            assistant.blocks[index].payload = streamingText
            assistant.blocks[index].isComplete = true
        } else {
            assistant.blocks.append(.text(streamingText))
        }
        for index in assistant.blocks.indices where assistant.blocks[index].kind == .toolCall {
            assistant.blocks[index].isComplete = true
        }
        try conversation.updateMessage(assistant)

        try conversation.completeGeneration()
        persistConversation()
    }

    private func persistConversation() {
        guard let persistence else { return }

        do {
            try persistence(conversation)
            persistenceError = nil
        } catch {
            persistenceError = "Couldn’t save this conversation."
        }
    }

    private func requestToolApproval(for call: ContentBlock) async -> Bool {
        guard let callID = call.attributes["callID"],
              let name = call.attributes["name"]
        else {
            return false
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingToolApproval = ToolApprovalRequest(
                    id: callID,
                    name: name,
                    arguments: call.payload
                )
                toolApprovalContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.denyPendingToolApproval()
            }
        }
    }

    private func denyPendingToolApproval() {
        toolApprovalContinuation?.resume(returning: false)
        toolApprovalContinuation = nil
        pendingToolApproval = nil
    }

    private func message(for error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .invalidConfiguration(let message), .remote(let message):
                return message
            case .missingCredential:
                return "Add a provider credential before sending a message."
            case .invalidResponse:
                return "The provider returned an invalid response."
            case .httpStatus(let status, let message):
                if status == 429 {
                    if let message, !message.isEmpty {
                        return "Rate limit reached. \(message)"
                    }
                    return "Rate limit reached. Try again in a moment."
                }
                return message ?? "The provider returned HTTP status \(status)."
            case .malformedEvent:
                return "The provider returned a malformed stream event."
            }
        }
        return error.localizedDescription
    }
}
