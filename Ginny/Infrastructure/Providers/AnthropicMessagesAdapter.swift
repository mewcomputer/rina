import Foundation

struct AnthropicMessagesStreamParser: Sendable {
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
        case "content_block_delta":
            guard let delta = dictionary["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String,
                  !text.isEmpty
            else {
                return []
            }
            return [.textDelta(text)]
        case "message_delta":
            guard let delta = dictionary["delta"] as? [String: Any],
                  let reason = delta["stop_reason"] as? String
            else {
                return []
            }
            return [.finish(reason: reason)]
        case "message_stop":
            return [.responseEnded]
        case "ping", "content_block_start", "content_block_stop":
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
                AnthropicMessage(role: "user", content: message.content)
            case .assistant:
                AnthropicMessage(role: "assistant", content: message.content)
            case .system:
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
                        throw ProviderError.httpStatus(response.statusCode, message: nil)
                    }

                    var sseParser = ServerSentEventParser()
                    let streamParser = AnthropicMessagesStreamParser()
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
    let content: String
}

private extension ProviderStreamEvent {
    var isTextDelta: Bool {
        if case .textDelta = self {
            return true
        }
        return false
    }
}
