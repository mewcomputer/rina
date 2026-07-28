import SwiftStreamingMarkdown
import SwiftUI

struct ChatView: View {
    @State private var draft = ""
    @State private var messages: [ChatMessage] = []
    @State private var activeResponse: ActiveResponse?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
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
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Conversation")
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, activeResponse == nil else { return }

        messages.append(ChatMessage(role: .user, text: prompt))
        draft = ""

        let response = ActiveResponse()
        activeResponse = response

        Task { @MainActor in
            let reply = "I received: **\(prompt)**\n\nThe live provider will plug in here next."
            var snapshot = ""

            for character in reply {
                try? await Task.sleep(for: .milliseconds(18))
                snapshot.append(character)
                response.source.yield(snapshot)
            }

            response.source.finish()
            messages.append(ChatMessage(role: .assistant, text: reply))
            activeResponse = nil
        }
    }
}

private struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
private struct ActiveResponse {
    let source = ChatResponseSource()
}

private struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        Group {
            if message.role == .user {
                Text(message.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                MarkdownView(text: message.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }
}
