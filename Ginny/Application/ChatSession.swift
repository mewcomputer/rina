import Combine
import Foundation

@MainActor
final class ChatSession: ObservableObject {
    @Published private(set) var conversation: Conversation
    @Published private(set) var streamingText = ""
    @Published private(set) var errorMessage: String?

    private var provider: (any ProviderAdapter)?

    init(
        provider: (any ProviderAdapter)? = nil,
        conversation: Conversation = Conversation()
    ) {
        self.provider = provider
        self.conversation = conversation
    }

    func configure(provider: any ProviderAdapter) {
        self.provider = provider
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

        errorMessage = nil
        streamingText = ""

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

            let request = ProviderRequest(
                messages: conversation.messages.dropLast().map {
                    ProviderMessage(
                        role: ProviderMessageRole(rawValue: $0.role.rawValue) ?? .user,
                        content: $0.blocks.map(\.payload).joined()
                    )
                }
            )

            for try await event in provider.stream(for: request) {
                try handle(event: event)
            }

            if conversation.generationState == .streaming {
                try finishGeneration()
            }
        } catch is CancellationError {
            try? conversation.cancelGeneration()
        } catch {
            errorMessage = message(for: error)
            try? conversation.failGeneration()
        }
    }

    private func handle(event: ProviderStreamEvent) throws {
        switch event {
        case .responseStarted:
            if conversation.generationState == .preparing {
                try conversation.beginStreaming()
            }
        case .textDelta(let delta):
            if conversation.generationState == .preparing {
                try conversation.beginStreaming()
            }
            guard var assistant = conversation.messages.last,
                  assistant.role == .assistant,
                  var block = assistant.blocks.first
            else {
                return
            }

            streamingText.append(delta)
            block.payload = streamingText
            block.isComplete = false
            assistant.blocks = [block]
            try conversation.updateMessage(assistant)
        case .finish:
            break
        case .responseEnded:
            try finishGeneration()
        }
    }

    private func finishGeneration() throws {
        guard var assistant = conversation.messages.last,
              assistant.role == .assistant,
              var block = assistant.blocks.first
        else {
            return
        }

        block.payload = streamingText
        block.isComplete = true
        assistant.blocks = [block]
        try conversation.updateMessage(assistant)

        if conversation.generationState == .streaming {
            try conversation.completeGeneration()
        }
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
                return message ?? "The provider returned HTTP status \(status)."
            case .malformedEvent:
                return "The provider returned a malformed stream event."
            }
        }
        return error.localizedDescription
    }
}
