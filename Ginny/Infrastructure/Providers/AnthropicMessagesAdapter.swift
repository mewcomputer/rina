import Foundation

struct AnthropicMessagesStreamParser: Sendable {
    let provider: ProviderID
    private var toolCallIDs: [Int: String] = [:]

    init(provider: ProviderID = .umans) {
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

            switch block["type"] as? String {
            case "tool_use":
                guard let id = block["id"] as? String,
                      let name = block["name"] as? String
                else {
                    throw ProviderError.malformedEvent
                }
                toolCallIDs[index] = id
                return [.toolCallDelta(
                    ProviderToolCallDelta(
                        provider: provider,
                        id: id,
                        name: name,
                        arguments: nil
                    )
                )]
            case "thinking":
                guard let thinking = block["thinking"] as? String,
                      !thinking.isEmpty
                else {
                    return []
                }
                return [.continuationDelta(
                    ProviderContinuationDelta(
                        provider: provider,
                        id: "block-\(index)",
                        kind: "reasoning",
                        field: "thinking",
                        value: thinking,
                        operation: .replace
                    )
                )]
            case "redacted_thinking":
                guard let data = block["data"] as? String else {
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
            default:
                return []
            }
        case "content_block_delta":
            guard let delta = dictionary["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String
            else {
                return []
            }

            let index = dictionary["index"] as? Int ?? 0
            switch deltaType {
            case "thinking_delta":
                guard let thinking = (delta["thinking"] as? String ?? delta["text"] as? String),
                      !thinking.isEmpty
                else {
                    return []
                }
                return [.continuationDelta(
                    ProviderContinuationDelta(
                        provider: provider,
                        id: "block-\(index)",
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
                        id: "block-\(index)",
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
            case "input_json_delta":
                guard let id = toolCallIDs[index],
                      let arguments = delta["partial_json"] as? String
                else {
                    throw ProviderError.malformedEvent
                }
                return [.toolCallDelta(
                    ProviderToolCallDelta(
                        provider: provider,
                        id: id,
                        name: nil,
                        arguments: arguments
                    )
                )]
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

    var supportsTools: Bool { configuration.supportsTools ?? true }

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
        let messages = try request.messages.compactMap { message -> AnthropicMessage? in
            switch message.role {
            case .user:
                try AnthropicMessage(message: message, provider: configuration.provider)
            case .assistant:
                try AnthropicMessage(message: message, provider: configuration.provider)
            case .system:
                nil
            case .tool:
                try AnthropicMessage(message: message, provider: configuration.provider)
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

        let toolDefinitions = request.tools.isEmpty || configuration.supportsTools == false
            ? nil
            : request.tools.map(AnthropicToolDefinition.init)
        let body = AnthropicMessagesRequestBody(
            model: configuration.model,
            maxTokens: 32_768,
            system: systemMessages.isEmpty ? nil : systemMessages.joined(separator: "\n"),
            messages: messages,
            tools: toolDefinitions,
            thinking: configuration.thinkingLevel?.anthropicThinking,
            outputConfig: configuration.thinkingLevel?.anthropicOutputConfig,
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
                    var streamParser = AnthropicMessagesStreamParser(provider: configuration.provider)
                    var didStartResponse = false
                    var didEndResponse = false
                    for try await byte in response.bytes {
                        for event in sseParser.append([byte]) {
                            for mappedEvent in try streamParser.parse(event) {
                                if mappedEvent == .responseStarted || mappedEvent.startsResponse {
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
                            if mappedEvent == .responseStarted || mappedEvent.startsResponse {
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
    let tools: [AnthropicToolDefinition]?
    let thinking: AnthropicThinking?
    let outputConfig: AnthropicOutputConfig?
    let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case thinking
        case outputConfig = "output_config"
        case stream
    }
}

private struct AnthropicThinking: Encodable {
    let type: String
}

private struct AnthropicOutputConfig: Encodable {
    let effort: String
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicMessageContent

    init(message: ProviderMessage, provider: ProviderID) throws {
        switch message.role {
        case .user:
            role = "user"
            content = .text(message.content)
        case .assistant:
            role = "assistant"
            var blocks = message.continuations
                .filter { $0.provider == provider && $0.kind == "reasoning" }
                .map(AnthropicContentBlock.init(continuation:))
            if !message.content.isEmpty {
                blocks.append(.text(message.content))
            }
            for toolCall in message.toolCalls {
                blocks.append(try AnthropicContentBlock.toolUse(call: toolCall))
            }
            content = blocks.isEmpty ? .text("") : .blocks(blocks)
        case .tool:
            role = "user"
            content = .blocks([
                .toolResult(
                    content: message.content,
                    callID: message.toolCallID ?? "",
                    isError: message.toolResultIsError == true
                )
            ])
        case .system:
            throw ProviderError.invalidConfiguration("System messages must be sent through the system field.")
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
    let id: String?
    let name: String?
    let input: ProviderJSONValue?
    let toolUseID: String?
    let content: String?
    let isError: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case thinking
        case signature
        case data
        case text
        case id
        case name
        case input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    private init(
        type: String,
        thinking: String?,
        signature: String?,
        data: String?,
        text: String?,
        id: String? = nil,
        name: String? = nil,
        input: ProviderJSONValue? = nil,
        toolUseID: String? = nil,
        content: String? = nil,
        isError: Bool? = nil
    ) {
        self.type = type
        self.thinking = thinking
        self.signature = signature
        self.data = data
        self.text = text
        self.id = id
        self.name = name
        self.input = input
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
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

    static func toolUse(call: ProviderToolCall) throws -> AnthropicContentBlock {
        let input: ProviderJSONValue
        if let data = call.arguments.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ProviderJSONValue.self, from: data)
        {
            input = decoded
        } else {
            input = .object([:])
        }
        return AnthropicContentBlock(
            type: "tool_use",
            thinking: nil,
            signature: nil,
            data: nil,
            text: nil,
            id: call.id,
            name: call.name,
            input: input
        )
    }

    static func toolResult(content: String, callID: String, isError: Bool) -> AnthropicContentBlock {
        AnthropicContentBlock(
            type: "tool_result",
            thinking: nil,
            signature: nil,
            data: nil,
            text: nil,
            toolUseID: callID,
            content: content,
            isError: isError ? true : nil
        )
    }

    init(continuation: ProviderContinuation) {
        if let data = continuation.fields["data"] {
            type = "redacted_thinking"
            thinking = nil
            signature = nil
            self.data = data
            text = nil
            id = nil
            name = nil
            input = nil
            toolUseID = nil
            content = nil
            isError = nil
        } else {
            type = "thinking"
            thinking = continuation.fields["thinking"] ?? ""
            signature = continuation.fields["signature"]
            data = nil
            text = nil
            id = nil
            name = nil
            input = nil
            toolUseID = nil
            content = nil
            isError = nil
        }
    }
}

private struct AnthropicToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    init(_ definition: ProviderToolDefinition) {
        name = definition.name
        description = definition.description
        inputSchema = definition.inputSchema
    }
}

private extension ThinkingLevel {
    var anthropicThinking: AnthropicThinking? {
        switch self {
        case .off:
            nil
        case .on, .low, .medium, .high, .max:
            AnthropicThinking(type: "adaptive")
        }
    }

    var anthropicOutputConfig: AnthropicOutputConfig? {
        switch self {
        case .off, .on:
            nil
        case .low, .medium, .high, .max:
            AnthropicOutputConfig(effort: rawValue)
        }
    }
}

private extension ProviderStreamEvent {
    var startsResponse: Bool {
        switch self {
        case .textDelta, .continuationDelta, .toolCallDelta:
            true
        default:
            false
        }
    }
}
