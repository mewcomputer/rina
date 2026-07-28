import Foundation

struct AnthropicMessagesStreamParser: Sendable {
    let provider: ProviderID

    init(provider: ProviderID = .umans) {
        self.provider = provider
    }

    func parse(_ event: ServerSentEvent) throws -> [ProviderStreamEvent] {
        if event.data == "[DONE]" {
            return [.responseEnded]
        }

        guard let data = event.data.data(using: .utf8) else {
            throw ProviderError.malformedEvent
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderError.malformedEvent
        }
        guard let dictionary = object as? [String: Any],
              let type = dictionary["type"] as? String
        else {
            throw ProviderError.malformedEvent
        }

        if type == "error",
           let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            throw ProviderError.remote(message: message)
        }

        switch type {
        case "message_start":
            return [.responseStarted]
        case "content_block_start":
            guard let block = dictionary["content_block"] as? [String: Any]
            else {
                return []
            }
            let index = dictionary["index"] as? Int ?? 0

            guard block["type"] as? String == "redacted_thinking",
                  let data = block["data"] as? String
            else {
                return []
            }

            return [.continuationDelta(
                ProviderContinuationDelta(
                    provider: provider,
                    id: "block-\(index)",
                    kind: "reasoning",
                    field: "data",
                    value: data,
                    operation: .replace
                )
            )]
        case "content_block_delta":
            guard let delta = dictionary["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String
            else {
                return []
            }

            let index = dictionary["index"] as? Int ?? 0
            let id = "block-\(index)"
            switch deltaType {
            case "thinking_delta":
                guard let thinking = delta["thinking"] as? String, !thinking.isEmpty else {
                    return []
                }
                return [.continuationDelta(
                    ProviderContinuationDelta(
                        provider: provider,
                        id: id,
                        kind: "reasoning",
                        field: "thinking",
                        value: thinking,
                        operation: .append
                    )
                )]
            case "signature_delta":
                guard let signature = delta["signature"] as? String, !signature.isEmpty else {
                    return []
                }
                return [.continuationDelta(
                    ProviderContinuationDelta(
                        provider: provider,
                        id: id,
                        kind: "reasoning",
                        field: "signature",
                        value: signature,
                        operation: .append
                    )
                )]
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else {
                    return []
                }
                return [.textDelta(text)]
            default:
                return []
            }
        case "message_delta":
            guard let delta = dictionary["delta"] as? [String: Any],
                  let reason = delta["stop_reason"] as? String
            else {
                return []
            }
            return [.finish(reason: reason)]
        case "message_stop":
            return [.responseEnded]
        case "ping", "content_block_stop":
            return []
        default:
            return []
        }
    }
}

struct AnthropicMessagesAdapter: ProviderAdapter {
    let configuration: ProviderConfiguration
    let credentialStore: any CredentialStore
    let transport: any StreamingTransport

    var supportsTools: Bool { false }

    init(
        configuration: ProviderConfiguration,
        credentialStore: any CredentialStore,
        transport: any StreamingTransport
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.transport = transport
    }

    func makeRequest(for request: ProviderRequest) throws -> URLRequest {
        let isLocalDevelopmentEndpoint = configuration.endpoint.scheme == "http"
            && ["localhost", "127.0.0.1"].contains(configuration.endpoint.host ?? "")
        guard configuration.endpoint.scheme == "https" || isLocalDevelopmentEndpoint else {
            throw ProviderError.invalidConfiguration(
                "Use HTTPS, or a localhost endpoint for local development."
            )
        }
        guard !configuration.model.isEmpty else {
            throw ProviderError.invalidConfiguration("A model is required.")
        }
        guard let credential = try credentialStore.credential(for: configuration.credentialID),
              !credential.isEmpty
        else {
            throw ProviderError.missingCredential
        }

        let systemMessages = request.messages
            .filter { $0.role == .system }
            .map(\.content)
        let messages = request.messages.compactMap { message -> AnthropicMessage? in
            switch message.role {
            case .user:
                AnthropicMessage(message: message, provider: configuration.provider)
            case .assistant:
                AnthropicMessage(message: message, provider: configuration.provider)
            case .system:
                nil
            case .tool:
                nil
            }
        }
        guard !messages.isEmpty else {
            throw ProviderError.invalidConfiguration("At least one user or assistant message is required.")
        }

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(credential, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = AnthropicMessagesRequestBody(
            model: configuration.model,
            maxTokens: 8_192,
            system: systemMessages.isEmpty ? nil : systemMessages.joined(separator: "\n"),
            messages: messages,
            stream: true
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeRequest(for: request)
                    let response = try await transport.response(for: urlRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        let data = try await response.data()
                        throw ProviderError.httpStatus(
                            response.statusCode,
                            message: providerErrorMessage(from: data)
                        )
                    }

                    var sseParser = ServerSentEventParser()
                    let streamParser = AnthropicMessagesStreamParser(provider: configuration.provider)
                    var didStartResponse = false
                    var didEndResponse = false
                    for try await byte in response.bytes {
                        for event in sseParser.append([byte]) {
                            for mappedEvent in try streamParser.parse(event) {
                                if mappedEvent == .responseStarted || mappedEvent.isTextDelta {
                                    didStartResponse = true
                                }
                                if mappedEvent == .responseEnded {
                                    didEndResponse = true
                                }
                                continuation.yield(mappedEvent)
                            }
                        }
                    }

                    for event in sseParser.finish() {
                        for mappedEvent in try streamParser.parse(event) {
                            if mappedEvent == .responseStarted || mappedEvent.isTextDelta {
                                didStartResponse = true
                            }
                            if mappedEvent == .responseEnded {
                                didEndResponse = true
                            }
                            continuation.yield(mappedEvent)
                        }
                    }
                    guard didStartResponse else {
                        throw ProviderError.invalidResponse
                    }
                    if !didEndResponse {
                        continuation.yield(.responseEnded)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct AnthropicMessagesRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicMessageContent

    init(message: ProviderMessage, provider: ProviderID) {
        role = message.role.rawValue
        let reasoningBlocks = message.continuations
            .filter { $0.provider == provider && $0.kind == "reasoning" }
            .map(AnthropicContentBlock.init(continuation:))
        if reasoningBlocks.isEmpty {
            content = .text(message.content)
        } else {
            var blocks = reasoningBlocks
            if !message.content.isEmpty {
                blocks.append(.text(message.content))
            }
            content = .blocks(blocks)
        }
    }
}

private enum AnthropicMessageContent: Encodable {
    case text(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .blocks(let blocks):
            var container = encoder.unkeyedContainer()
            for block in blocks {
                try container.encode(block)
            }
        }
    }
}

private struct AnthropicContentBlock: Encodable {
    let type: String
    let thinking: String?
    let signature: String?
    let data: String?
    let text: String?

    private init(
        type: String,
        thinking: String?,
        signature: String?,
        data: String?,
        text: String?
    ) {
        self.type = type
        self.thinking = thinking
        self.signature = signature
        self.data = data
        self.text = text
    }

    static func text(_ text: String) -> AnthropicContentBlock {
        AnthropicContentBlock(
            type: "text",
            thinking: nil,
            signature: nil,
            data: nil,
            text: text
        )
    }

    init(continuation: ProviderContinuation) {
        if let data = continuation.fields["data"] {
            type = "redacted_thinking"
            thinking = nil
            signature = nil
            self.data = data
            text = nil
        } else {
            type = "thinking"
            thinking = continuation.fields["thinking"] ?? ""
            signature = continuation.fields["signature"]
            data = nil
            text = nil
        }
    }
}

private extension ProviderStreamEvent {
    var isTextDelta: Bool {
        if case .textDelta = self {
            return true
        }
        return false
    }
}
