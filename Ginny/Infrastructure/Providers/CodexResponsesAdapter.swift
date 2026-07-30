import Foundation

struct CodexResponsesStreamParser: Sendable {
    let provider: ProviderID
    let model: String?
    private var toolNames: [String: String] = [:]
    private var toolArguments: [String: String] = [:]
    private var itemToCallIDs: [String: String] = [:]
    private var emittedToolArguments: [String: String] = [:]
    private var emittedToolCallIDs: Set<String> = []
    private var pendingToolCallIDs: Set<String> = []
    private var sawToolCall = false
    private(set) var receivedTerminalEvent = false

    init(provider: ProviderID = .codex, model: String? = nil) {
        self.provider = provider
        self.model = model
    }

    mutating func parse(_ event: ServerSentEvent) throws -> [ProviderStreamEvent] {
        if event.data == "[DONE]" {
            guard receivedTerminalEvent else {
                throw ProviderError.invalidResponse
            }
            return []
        }
        guard !receivedTerminalEvent else {
            throw ProviderError.invalidResponse
        }

        guard let data = event.data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderError.malformedEvent
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            throw ProviderError.remote(message: message)
        }

        guard let type = object["type"] as? String else {
            throw ProviderError.malformedEvent
        }

        switch type {
        case "response.created", "response.in_progress":
            return []
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String else {
                throw ProviderError.malformedEvent
            }
            guard !delta.isEmpty else { return [] }
            return [.textDelta(delta)]
        case "response.reasoning_summary_text.delta":
            guard let delta = object["delta"] as? String,
                  let id = Self.nonEmptyString(object["item_id"] as? String)
            else { throw ProviderError.malformedEvent }
            guard !delta.isEmpty else { return [] }
            return [.continuationDelta(
                ProviderContinuationDelta(
                    provider: provider,
                    id: id,
                    kind: "reasoning",
                    field: "text",
                    value: delta,
                    operation: .append
                )
            )]
        case "response.output_item.added":
            guard let item = object["item"] as? [String: Any],
                  let itemType = item["type"] as? String
            else { throw ProviderError.malformedEvent }

            if itemType == "reasoning" {
                return try reasoningEvents(from: item)
            }

            guard itemType == "function_call" else { return [] }
            if let arguments = item["arguments"], !(arguments is String) {
                throw ProviderError.malformedEvent
            }
            if let name = item["name"], !(name is String) {
                throw ProviderError.malformedEvent
            }
            let (itemID, id) = try registerFunctionCall(item)
            sawToolCall = true
            pendingToolCallIDs.insert(id)
            if let name = item["name"] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                toolNames[id] = name
            }
            if let arguments = item["arguments"] as? String, !arguments.isEmpty {
                toolArguments[id, default: ""] += arguments
            }
            itemToCallIDs[itemID] = id
            return emitToolCallIfNamed(id: id)
        case "response.output_item.done":
            guard let item = object["item"] as? [String: Any],
                  let itemType = item["type"] as? String
            else { throw ProviderError.malformedEvent }
            if itemType == "reasoning" {
                return try reasoningEvents(from: item)
            }
            guard itemType == "function_call" else { return [] }
            guard let arguments = item["arguments"] as? String else {
                throw ProviderError.malformedEvent
            }
            if let name = item["name"], !(name is String) {
                throw ProviderError.malformedEvent
            }
            let (itemID, id) = try registerFunctionCall(item)
            sawToolCall = true
            pendingToolCallIDs.insert(id)
            if let name = item["name"] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                toolNames[id] = name
            }
            toolArguments[id] = arguments
            itemToCallIDs[itemID] = id
            var events = emitToolCallIfNamed(id: id)
            events.append(contentsOf: try finalizeToolCall(id: id, arguments: toolArguments[id]))
            return events
        case "response.reasoning_summary_text.done":
            guard let text = object["text"] as? String,
                  let id = Self.nonEmptyString(object["item_id"] as? String)
            else { throw ProviderError.malformedEvent }
            guard !text.isEmpty else { return [] }
            return [.continuationDelta(
                ProviderContinuationDelta(
                    provider: provider,
                    id: id,
                    kind: "reasoning",
                    field: "text",
                    value: text,
                    operation: .replace
                )
            )]
        case "response.function_call_arguments.delta":
            guard let delta = object["delta"] as? String,
                  let rawID = Self.nonEmptyString(object["call_id"] as? String)
                    ?? Self.nonEmptyString(object["item_id"] as? String)
            else {
                throw ProviderError.malformedEvent
            }
            let id = itemToCallIDs[rawID] ?? rawID
            sawToolCall = true
            pendingToolCallIDs.insert(id)
            toolArguments[id, default: ""] += delta
            return emitToolCallIfNamed(id: id, arguments: delta)
        case "response.function_call_arguments.done":
            guard let arguments = object["arguments"] as? String,
                  let rawID = Self.nonEmptyString(object["call_id"] as? String)
                    ?? Self.nonEmptyString(object["item_id"] as? String)
            else {
                throw ProviderError.malformedEvent
            }
            let id = itemToCallIDs[rawID] ?? rawID
            sawToolCall = true
            pendingToolCallIDs.insert(id)
            if let name = object["name"] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                toolNames[id] = name
            }
            toolArguments[id] = arguments
            var events = emitToolCallIfNamed(id: id)
            events.append(contentsOf: try finalizeToolCall(id: id, arguments: arguments))
            return events
        case "response.completed":
            return try terminalEvents()
        case "response.failed", "response.incomplete":
            let response = object["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            let message = error?["message"] as? String
                ?? response?["status"] as? String
                ?? "Codex response failed."
            throw ProviderError.remote(message: message)
        default:
            return []
        }
    }

    private mutating func emitToolCallIfNamed(
        id: String,
        arguments: String? = nil
    ) -> [ProviderStreamEvent] {
        guard let name = toolNames[id] else {
            return []
        }
        if emittedToolCallIDs.contains(id) {
            guard let arguments, !arguments.isEmpty else {
                return []
            }
            emittedToolArguments[id, default: ""] += arguments
            return [.toolCallDelta(
                ProviderToolCallDelta(
                    provider: provider,
                    id: id,
                    name: name,
                    arguments: arguments
                )
            )]
        }
        emittedToolCallIDs.insert(id)
        emittedToolArguments[id] = arguments ?? toolArguments[id] ?? ""
        return [.toolCallDelta(
            ProviderToolCallDelta(
                provider: provider,
                id: id,
                name: name,
                arguments: arguments ?? toolArguments[id]
            )
        )]
    }

    private mutating func finalizeToolCall(
        id: String,
        arguments: String?
    ) throws -> [ProviderStreamEvent] {
        guard let name = toolNames[id] else {
            return []
        }

        let finalArguments = arguments ?? toolArguments[id] ?? ""
        let emittedArguments = emittedToolArguments[id] ?? ""
        var events: [ProviderStreamEvent] = []
        if finalArguments != emittedArguments {
            guard finalArguments.hasPrefix(emittedArguments) else {
                throw ProviderError.malformedEvent
            }
            let suffix = String(finalArguments.dropFirst(emittedArguments.count))
            if !suffix.isEmpty {
                events.append(.toolCallDelta(
                    ProviderToolCallDelta(
                        provider: provider,
                        id: id,
                        name: name,
                        arguments: suffix
                    )
                ))
            }
            emittedToolArguments[id] = finalArguments
        }
        pendingToolCallIDs.remove(id)
        return events
    }

    private mutating func terminalEvents() throws -> [ProviderStreamEvent] {
        guard pendingToolCallIDs.isEmpty else {
            throw ProviderError.remote(message: "Codex returned an incomplete tool call.")
        }
        guard !receivedTerminalEvent else { return [] }
        receivedTerminalEvent = true
        return [
            .finish(reason: sawToolCall ? "tool_calls" : "stop"),
            .responseEnded,
        ]
    }

    private mutating func registerFunctionCall(
        _ item: [String: Any]
    ) throws -> (itemID: String, callID: String) {
        guard let itemID = Self.nonEmptyString(item["id"] as? String),
              let callID = Self.nonEmptyString(item["call_id"] as? String)
        else {
            throw ProviderError.malformedEvent
        }

        itemToCallIDs[itemID] = callID
        if itemID != callID {
            migrateCallState(from: itemID, to: callID)
        }
        return (itemID, callID)
    }

    private mutating func migrateCallState(from sourceID: String, to targetID: String) {
        if let name = toolNames.removeValue(forKey: sourceID) {
            toolNames[targetID] = name
        }
        if let arguments = toolArguments.removeValue(forKey: sourceID) {
            toolArguments[targetID] = arguments
        }
        if let arguments = emittedToolArguments.removeValue(forKey: sourceID) {
            emittedToolArguments[targetID] = arguments
        }
        if emittedToolCallIDs.remove(sourceID) != nil {
            emittedToolCallIDs.insert(targetID)
        }
        if pendingToolCallIDs.remove(sourceID) != nil {
            pendingToolCallIDs.insert(targetID)
        }
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return value
    }

    private func reasoningEvents(from item: [String: Any]) throws -> [ProviderStreamEvent] {
        guard let id = Self.nonEmptyString(item["id"] as? String) else {
            throw ProviderError.malformedEvent
        }
        var events: [ProviderStreamEvent] = []

        if let model, item["encrypted_content"] as? String != nil {
            events.append(.continuationDelta(
                ProviderContinuationDelta(
                    provider: provider,
                    id: id,
                    kind: "reasoning",
                    field: "model",
                    value: model,
                    operation: .replace,
                    isPrivate: true
                )
            ))
        }

        if let summary = item["summary"] as? [[String: Any]] {
            let text = summary.compactMap { part -> String? in
                guard part["type"] as? String == "summary_text",
                      let text = part["text"] as? String,
                      !text.isEmpty
                else {
                    return nil
                }
                return text
            }.joined(separator: "\n\n")
            if !text.isEmpty {
                events.append(.continuationDelta(
                    ProviderContinuationDelta(
                        provider: provider,
                        id: id,
                        kind: "reasoning",
                        field: "text",
                        value: text,
                        operation: .replace
                    )
                ))
            }
        }

        if let encryptedContent = item["encrypted_content"] as? String,
           !encryptedContent.isEmpty
        {
            events.append(.continuationDelta(
                ProviderContinuationDelta(
                    provider: provider,
                    id: id,
                    kind: "reasoning",
                    field: "encrypted_content",
                    value: encryptedContent,
                    operation: .replace,
                    isPrivate: true
                )
            ))
        }
        return events
    }
}

struct CodexResponsesAdapter: ProviderAdapter {
    let configuration: ProviderConfiguration
    let oauthService: CodexOAuthService
    let transport: any StreamingTransport

    var supportsTools: Bool { configuration.supportsTools ?? true }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let accessToken = try await oauthService.accessToken()
                    let urlRequest = try makeRequest(for: request, accessToken: accessToken)
                    let response = try await transport.response(for: urlRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        let data = try await response.data()
                        if response.statusCode == 401 {
                            await oauthService.signOut()
                        }
                        throw ProviderError.httpStatus(
                            response.statusCode,
                            message: providerErrorMessage(from: data)
                        )
                    }

                    continuation.yield(.responseStarted)
                    var sseParser = ServerSentEventParser()
                    var streamParser = CodexResponsesStreamParser(
                        provider: configuration.provider,
                        model: configuration.model
                    )
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
                    guard streamParser.receivedTerminalEvent else {
                        throw ProviderError.invalidResponse
                    }
                    continuation.finish()
                } catch CodexOAuthError.signedOut {
                    continuation.finish(throwing: ProviderError.missingCredential)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(
        for request: ProviderRequest,
        accessToken: String
    ) throws -> URLRequest {
        let isLocalDevelopmentEndpoint = configuration.endpoint.scheme == "http"
            && ["localhost", "127.0.0.1"].contains(configuration.endpoint.host ?? "")
        guard configuration.endpoint.scheme == "https" || isLocalDevelopmentEndpoint else {
            throw ProviderError.invalidConfiguration(
                "Use HTTPS, or a localhost endpoint for local development."
            )
        }
        guard CodexOAuthService.isOfficialBackendEndpointURL(configuration.endpoint) else {
            throw ProviderError.invalidConfiguration(
                "Codex only supports the official ChatGPT endpoint."
            )
        }
        guard !configuration.model.isEmpty else {
            throw ProviderError.invalidConfiguration("A model is required.")
        }
        guard request.messages
            .flatMap(\.toolCalls)
            .allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw ProviderError.invalidConfiguration("Codex received a tool call without a name.")
        }
        guard request.messages
            .flatMap(\.toolCalls)
            .allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw ProviderError.invalidConfiguration("Codex received a tool call without an ID.")
        }
        guard request.messages
            .filter({ $0.role == .tool })
            .allSatisfy({
                guard let id = $0.toolCallID else { return false }
                return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw ProviderError.invalidConfiguration("Codex received a tool result without a call ID.")
        }
        guard request.messages
            .flatMap(\.continuations)
            .filter({ $0.provider == configuration.provider && $0.kind == "reasoning" })
            .allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw ProviderError.invalidConfiguration("Codex received reasoning state without an ID.")
        }
        guard request.tools
            .allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw ProviderError.invalidConfiguration("Codex received a tool definition without a name.")
        }

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "x-client-request-id")
        urlRequest.httpBody = try JSONEncoder().encode(
            CodexResponsesRequestBody(
                model: configuration.model,
                instructions: request.messages
                    .filter { $0.role == .system }
                    .map(\.content)
                    .joined(separator: "\n\n"),
                input: CodexInputItem.messages(
                    request.messages,
                    provider: configuration.provider,
                    model: configuration.model
                ),
                tools: supportsTools ? request.tools.map(CodexToolDefinition.init) : [],
                reasoning: configuration.thinkingLevel?.codexReasoning,
                include: ["reasoning.encrypted_content"],
                stream: true,
                store: false
            )
        )
        return urlRequest
    }
}

private struct CodexResponsesRequestBody: Encodable {
    let model: String
    let instructions: String
    let input: [CodexInputItem]
    let tools: [CodexToolDefinition]
    let reasoning: CodexReasoning?
    let include: [String]
    let stream: Bool
    let store: Bool
}

private enum CodexInputItem: Encodable {
    case message(role: String, content: String, contentType: String)
    case reasoning(id: String, summary: [CodexReasoningSummary], encryptedContent: String?)
    case functionCall(id: String, name: String, arguments: String)
    case functionOutput(id: String, output: String)

    static func messages(
        _ messages: [ProviderMessage],
        provider: ProviderID,
        model: String
    ) -> [CodexInputItem] {
        messages
            .filter { $0.role != .system }
            .flatMap { message in
                var items: [CodexInputItem] = []
                if message.role == .assistant {
                    let reasoningContinuations = message.continuations.filter {
                        $0.provider == provider && $0.kind == "reasoning"
                    }
                    let summary = reasoningContinuations.compactMap {
                        $0.shareableFields["thinking"] ?? $0.shareableFields["text"]
                    }.map { CodexReasoningSummary(text: $0) }
                    let encryptedContent = reasoningContinuations
                        .filter { $0.fields["model"] == model }
                        .compactMap { $0.fields["encrypted_content"] }
                        .last
                    if !summary.isEmpty || encryptedContent != nil {
                        items.append(.reasoning(
                            id: reasoningContinuations.first?.id ?? "reasoning",
                            summary: summary,
                            encryptedContent: encryptedContent
                        ))
                    }
                }
                if !message.content.isEmpty {
                    let contentType = message.role == .assistant ? "output_text" : "input_text"
                    items.append(.message(
                        role: message.role == .tool ? "user" : message.role.rawValue,
                        content: message.content,
                        contentType: contentType
                    ))
                }
                if message.role == .assistant {
                    items.append(contentsOf: message.toolCalls.map {
                        .functionCall(id: $0.id, name: $0.name, arguments: $0.arguments)
                    })
                }
                if message.role == .tool, let id = message.toolCallID {
                    items.removeAll()
                    items.append(.functionOutput(id: id, output: message.content))
                }
                return items
            }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .message(role, content, contentType):
            var container = encoder.container(keyedBy: MessageCodingKeys.self)
            try container.encode("message", forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode([CodexContent(type: contentType, text: content)], forKey: .content)
        case let .reasoning(id, summary, encryptedContent):
            var container = encoder.container(keyedBy: ReasoningCodingKeys.self)
            try container.encode("reasoning", forKey: .type)
            try container.encode(id, forKey: .id)
            if !summary.isEmpty {
                try container.encode(summary, forKey: .summary)
            }
            try container.encodeIfPresent(encryptedContent, forKey: .encryptedContent)
        case let .functionCall(id, name, arguments):
            var container = encoder.container(keyedBy: FunctionCallCodingKeys.self)
            try container.encode("function_call", forKey: .type)
            try container.encode(id, forKey: .callID)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case let .functionOutput(id, output):
            var container = encoder.container(keyedBy: FunctionOutputCodingKeys.self)
            try container.encode("function_call_output", forKey: .type)
            try container.encode(id, forKey: .callID)
            try container.encode(output, forKey: .output)
        }
    }

    private enum MessageCodingKeys: String, CodingKey {
        case type
        case role
        case content
    }

    private enum FunctionCallCodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case name
        case arguments
    }

    private enum FunctionOutputCodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case output
    }

    private enum ReasoningCodingKeys: String, CodingKey {
        case type
        case id
        case summary
        case encryptedContent = "encrypted_content"
    }
}

private struct CodexReasoningSummary: Encodable {
    let type = "summary_text"
    let text: String
}

private struct CodexContent: Encodable {
    let type: String
    let text: String
}

private struct CodexToolDefinition: Encodable {
    let type = "function"
    let name: String
    let description: String
    let parameters: JSONSchema

    init(_ definition: ProviderToolDefinition) {
        name = definition.name
        description = definition.description
        parameters = definition.inputSchema
    }
}

private struct CodexReasoning: Encodable {
    let effort: String
    let summary = "auto"
}

private extension ThinkingLevel {
    var codexReasoning: CodexReasoning? {
        switch self {
        case .off:
            nil
        case .on:
            CodexReasoning(effort: "medium")
        case .low, .medium, .high, .xhigh, .max, .ultra:
            CodexReasoning(effort: rawValue)
        }
    }
}
