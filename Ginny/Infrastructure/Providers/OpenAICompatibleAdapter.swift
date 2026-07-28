import Foundation

struct OpenAICompatibleStreamParser: Sendable {
    let provider: ProviderID
    private var toolCallIDs: [Int: String] = [:]

    init(provider: ProviderID = .openAICompatible) {
        self.provider = provider
    }

    mutating func parse(_ event: ServerSentEvent) throws -> [ProviderStreamEvent] {
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
            if let delta = choice["delta"] as? [String: Any] {
                if let reasoning = delta["reasoning_content"] as? String,
                   !reasoning.isEmpty
                {
                    events.append(.continuationDelta(
                        ProviderContinuationDelta(
                            provider: provider,
                            id: "reasoning",
                            kind: "reasoning",
                            field: "text",
                            value: reasoning,
                            operation: .append
                        )
                    ))
                }

                if let content = delta["content"] as? String,
                   !content.isEmpty
                {
                    events.append(.textDelta(content))
                }

                if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                    for toolCall in toolCalls {
                        guard let index = toolCall["index"] as? Int,
                              let function = toolCall["function"] as? [String: Any]
                        else {
                            continue
                        }

                        if let id = toolCall["id"] as? String, !id.isEmpty {
                            toolCallIDs[index] = id
                        }
                        guard let id = toolCallIDs[index] else {
                            throw ProviderError.malformedEvent
                        }
                        events.append(.toolCallDelta(
                            ProviderToolCallDelta(
                                provider: provider,
                                id: id,
                                name: function["name"] as? String,
                                arguments: function["arguments"] as? String
                            )
                        ))
                    }
                }
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

    var supportsTools: Bool { true }

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

        let toolDefinitions = try request.tools.isEmpty
            ? nil
            : request.tools.map(OpenAIToolDefinition.init)
        let body = OpenAICompatibleRequestBody(
            model: configuration.model,
            messages: request.messages.map {
                OpenAICompatibleMessage(message: $0, provider: configuration.provider)
            },
            maxTokens: 32_768,
            reasoningEffort: configuration.provider == .kimiCode
                && ["k3", "k3-256k"].contains(configuration.model)
                ? configuration.thinkingLevel?.reasoningEffort
                : nil,
            thinking: configuration.provider == .kimiCode
                ? configuration.thinkingLevel?.kimiThinking
                : nil,
            tools: toolDefinitions,
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

                    continuation.yield(.responseStarted)

                    var sseParser = ServerSentEventParser()
                    var streamParser = OpenAICompatibleStreamParser(provider: configuration.provider)
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
    let messages: [OpenAICompatibleMessage]
    let maxTokens: Int
    let reasoningEffort: String?
    let thinking: KimiThinking?
    let tools: [OpenAIToolDefinition]?
    let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
        case thinking
        case tools
        case stream
    }
}

private struct OpenAICompatibleMessage: Encodable {
    let role: String
    let content: String?
    let reasoningContent: String?
    let toolCalls: [OpenAIToolCall]?
    let toolCallID: String?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    init(message: ProviderMessage, provider: ProviderID) {
        role = message.role.rawValue
        content = message.content.isEmpty ? nil : message.content
        let reasoning = message.continuations
            .filter { $0.provider == provider && $0.kind == "reasoning" }
            .compactMap { $0.fields["text"] }
            .joined()
        reasoningContent = reasoning.isEmpty ? nil : reasoning
        toolCalls = message.toolCalls.isEmpty
            ? nil
            : message.toolCalls.map(OpenAIToolCall.init)
        toolCallID = message.toolCallID
    }
}

private struct OpenAIToolCall: Encodable {
    let id: String
    let type = "function"
    let function: OpenAIFunctionCall

    init(call: ProviderToolCall) {
        id = call.id
        function = OpenAIFunctionCall(name: call.name, arguments: call.arguments)
    }
}

private struct OpenAIFunctionCall: Encodable {
    let name: String
    let arguments: String
}

private struct OpenAIToolDefinition: Encodable {
    let type = "function"
    let function: OpenAIFunctionDefinition

    init(_ definition: ProviderToolDefinition) throws {
        function = OpenAIFunctionDefinition(
            name: definition.name,
            description: definition.description,
            parameters: try JSONDecoder().decode(
                JSONValue.self,
                from: Data(definition.inputSchema.utf8)
            )
        )
    }
}

private struct OpenAIFunctionDefinition: Encodable {
    let name: String
    let description: String
    let parameters: JSONValue
}

private indirect enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

private struct KimiThinking: Encodable {
    let type: String
}

private extension ThinkingLevel {
    var reasoningEffort: String? {
        switch self {
        case .low, .high, .max:
            rawValue
        case .off, .on:
            nil
        }
    }

    var kimiThinking: KimiThinking? {
        switch self {
        case .off:
            KimiThinking(type: "disabled")
        case .on:
            KimiThinking(type: "enabled")
        case .low, .high, .max:
            nil
        }
    }
}
