import Foundation

struct OpenAICompatibleStreamParser: Sendable {
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
        guard let dictionary = object as? [String: Any] else {
            throw ProviderError.malformedEvent
        }

        if let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            throw ProviderError.remote(message: message)
        }

        guard let choices = dictionary["choices"] as? [[String: Any]] else {
            throw ProviderError.malformedEvent
        }

        var events: [ProviderStreamEvent] = []
        for choice in choices {
            if let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String,
               !content.isEmpty
            {
                events.append(.textDelta(content))
            }

            if let finishReason = choice["finish_reason"] as? String {
                events.append(.finish(reason: finishReason))
            }
        }
        return events
    }
}

struct OpenAICompatibleAdapter: ProviderAdapter {
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

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")

        let body = OpenAICompatibleRequestBody(
            model: configuration.model,
            messages: request.messages,
            maxTokens: 32_768,
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

                    continuation.yield(.responseStarted)

                    var sseParser = ServerSentEventParser()
                    let streamParser = OpenAICompatibleStreamParser()
                    for try await byte in response.bytes {
                        for event in sseParser.append([byte]) {
                            for mappedEvent in try streamParser.parse(event) {
                                continuation.yield(mappedEvent)
                            }
                        }
                    }

                    for event in sseParser.finish() {
                        for mappedEvent in try streamParser.parse(event) {
                            continuation.yield(mappedEvent)
                        }
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

private struct OpenAICompatibleRequestBody: Encodable {
    let model: String
    let messages: [ProviderMessage]
    let maxTokens: Int
    let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}
