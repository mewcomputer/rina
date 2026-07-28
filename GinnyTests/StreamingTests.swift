import Foundation
import XCTest
@testable import Ginny

final class StreamingTests: XCTestCase {
    func testSSEParserHandlesEventsSplitAcrossChunks() throws {
        var parser = ServerSentEventParser()

        XCTAssertEqual(parser.append(Array("data: {\"value\":\"hel".utf8)), [])
        XCTAssertEqual(
            parser.append(Array("lo\"}\n\n".utf8)),
            [ServerSentEvent(data: "{\"value\":\"hello\"}")]
        )
    }

    func testSSEParserJoinsMultilineDataAndIgnoresComments() {
        var parser = ServerSentEventParser()

        let events = parser.append(
            Array(": keep-alive\ndata: first\ndata: second\n\n".utf8)
        )

        XCTAssertEqual(events, [ServerSentEvent(data: "first\nsecond")])
    }

    func testSSEParserFlushesFinalEventWithoutTrailingBlankLine() {
        var parser = ServerSentEventParser()

        _ = parser.append(Array("data: final".utf8))

        XCTAssertEqual(parser.finish(), [ServerSentEvent(data: "final")])
    }

    func testOpenAIStreamParserMapsTextAndDoneEvents() throws {
        var parser = OpenAICompatibleStreamParser()

        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"
                )
            ),
            [.textDelta("Hello")]
        )
        XCTAssertEqual(try parser.parse(ServerSentEvent(data: "[DONE]")), [.responseEnded])
    }

    func testOpenAIStreamParserMapsReasoningContentAsContinuationMetadata() throws {
        var parser = OpenAICompatibleStreamParser(provider: .kimiCode)

        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"choices\":[{\"delta\":{\"reasoning_content\":\"think\"}}]}"
                )
            ),
            [.continuationDelta(
                ProviderContinuationDelta(
                    provider: .kimiCode,
                    id: "reasoning",
                    kind: "reasoning",
                    field: "text",
                    value: "think",
                    operation: .append
                )
            )]
        )
    }

    func testOpenAIStreamParserMapsToolCallDeltas() throws {
        var parser = OpenAICompatibleStreamParser(provider: .kimiCode)

        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"name\":\"current_time\",\"arguments\":\"{}\"}}]}}]}"
                )
            ),
            [.toolCallDelta(
                ProviderToolCallDelta(
                    provider: .kimiCode,
                    id: "call-1",
                    name: "current_time",
                    arguments: "{}"
                )
            )]
        )

        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"more\"}}]}}]}"
                )
            ),
            [.toolCallDelta(
                ProviderToolCallDelta(
                    provider: .kimiCode,
                    id: "call-1",
                    name: nil,
                    arguments: "more"
                )
            )]
        )
    }

    func testOpenAIStreamParserMapsProviderError() {
        var parser = OpenAICompatibleStreamParser()

        XCTAssertThrowsError(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"error\":{\"message\":\"bad key\"}}"
                )
            )
        ) { error in
            XCTAssertEqual(error as? ProviderError, .remote(message: "bad key"))
        }
    }

    func testOpenAIAdapterSurfacesRateLimitMessage() async throws {
        let adapter = OpenAICompatibleAdapter(
            configuration: ProviderConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "example-model",
                credentialID: "primary"
            ),
            credentialStore: InMemoryCredentialStore(credentials: ["primary": "secret"]),
            transport: FixtureStreamingTransport(
                statusCode: 429,
                body: "{\"error\":{\"message\":\"Too many requests. Try again later.\"}}"
            )
        )

        do {
            for try await _ in adapter.stream(for: ProviderRequest(messages: [.user("Hello")])) {}
            XCTFail("Expected a rate-limit error")
        } catch {
            XCTAssertEqual(
                error as? ProviderError,
                .httpStatus(429, message: "Too many requests. Try again later.")
            )
        }
    }

    func testAnthropicStreamParserMapsMessageEvents() throws {
        var parser = AnthropicMessagesStreamParser()

        XCTAssertEqual(
            try parser.parse(ServerSentEvent(data: "{\"type\":\"message_start\"}")),
            [.responseStarted]
        )
        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}"
                )
            ),
            [.textDelta("Hello")]
        )
        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"plan\"}}"
                )
            ),
            [.continuationDelta(
                ProviderContinuationDelta(
                    provider: .umans,
                    id: "block-0",
                    kind: "reasoning",
                    field: "thinking",
                    value: "plan",
                    operation: .append
                )
            )]
        )
        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"signature_delta\",\"signature\":\"opaque\"}}"
                )
            ),
            [.continuationDelta(
                ProviderContinuationDelta(
                    provider: .umans,
                    id: "block-0",
                    kind: "reasoning",
                    field: "signature",
                    value: "opaque",
                    operation: .append
                )
            )]
        )
        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}"
                )
            ),
            [.finish(reason: "end_turn")]
        )
        XCTAssertEqual(
            try parser.parse(ServerSentEvent(data: "{\"type\":\"message_stop\"}")),
            [.responseEnded]
        )
        XCTAssertEqual(try parser.parse(ServerSentEvent(data: "[DONE]")), [.responseEnded])
    }

    func testAnthropicStreamParserMapsToolUseAndFragmentedArguments() throws {
        var parser = AnthropicMessagesStreamParser()

        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"current_time\",\"input\":{}}}"
                )
            ),
            [.toolCallDelta(
                ProviderToolCallDelta(
                    provider: .umans,
                    id: "toolu_1",
                    name: "current_time",
                    arguments: nil
                )
            )]
        )
        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\"}}"
                )
            ),
            [.toolCallDelta(
                ProviderToolCallDelta(
                    provider: .umans,
                    id: "toolu_1",
                    name: nil,
                    arguments: "{"
                )
            )]
        )
        XCTAssertEqual(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"}\"}}"
                )
            ),
            [.toolCallDelta(
                ProviderToolCallDelta(
                    provider: .umans,
                    id: "toolu_1",
                    name: nil,
                    arguments: "}"
                )
            )]
        )
    }

    func testAnthropicStreamParserMapsProviderError() {
        var parser = AnthropicMessagesStreamParser()

        XCTAssertThrowsError(
            try parser.parse(
                ServerSentEvent(
                    data: "{\"type\":\"error\",\"error\":{\"message\":\"bad key\"}}"
                )
            )
        ) { error in
            XCTAssertEqual(error as? ProviderError, .remote(message: "bad key"))
        }
    }

    func testAdapterTranslatesFragmentedSSEBytesIntoCanonicalEvents() async throws {
        let configuration = ProviderConfiguration(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            model: "example-model",
            credentialID: "primary"
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["primary": "secret"]),
            transport: FixtureStreamingTransport(
                statusCode: 200,
                body: "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\ndata: [DONE]\n\n"
            )
        )

        var events: [ProviderStreamEvent] = []
        for try await event in adapter.stream(for: ProviderRequest(messages: [.user("Hello")])) {
            events.append(event)
        }

        XCTAssertEqual(
            events,
            [.responseStarted, .textDelta("Hi"), .responseEnded]
        )
    }

    func testURLSessionTransportStreamsBytesFromTheResponse() async throws {
        StreamingURLProtocol.body = Data("data: fixture\n\n".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let transport = URLSessionStreamingTransport(session: session)

        var bytes: [UInt8] = []
        let response = try await transport.response(
            for: URLRequest(url: URL(string: "https://fixture.test/stream")!)
        )
        for try await byte in response.bytes {
            bytes.append(byte)
        }

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "data: fixture\n\n")
    }

    func testOpenAIRequestIncludesBearerAuthenticationAndStreaming() throws {
        let configuration = ProviderConfiguration(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            model: "example-model",
            credentialID: "primary"
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["primary": "secret"]),
            transport: UnusedStreamingTransport()
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [.user("Hello")])
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(object["model"] as? String, "example-model")
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual(object["max_tokens"] as? Int, 32_768)
    }

    func testOpenAIRequestIncludesToolDefinitions() throws {
        let configuration = ProviderConfiguration(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            model: "example-model",
            credentialID: "primary"
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["primary": "secret"]),
            transport: UnusedStreamingTransport()
        )
        let tool = ProviderToolDefinition(
            name: "current_time",
            description: "Returns the current time.",
            inputSchema: "{\"type\":\"object\",\"properties\":{}}"
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [.user("Hello")], tools: [tool])
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertEqual(function["name"] as? String, "current_time")
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertNotNil(parameters["properties"] as? [String: Any])
    }

    func testOpenAIRequestPreservesAssistantToolCallsAndToolResults() throws {
        let configuration = ProviderConfiguration(
            endpoint: URL(string: "https://example.com/v1/chat/completions")!,
            model: "example-model",
            credentialID: "primary"
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["primary": "secret"]),
            transport: UnusedStreamingTransport()
        )
        let call = ProviderToolCall(
            id: "call-1",
            name: "current_time",
            arguments: "{}",
            isComplete: true
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [
                .assistant("", toolCalls: [call]),
                .tool("1970-01-01T00:00:00Z", callID: "call-1"),
            ])
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(messages.first)
        let toolCalls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        let function = try XCTUnwrap(toolCalls.first?["function"] as? [String: Any])
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        XCTAssertEqual(toolCalls.first?["id"] as? String, "call-1")
        XCTAssertEqual(function["name"] as? String, "current_time")
        XCTAssertEqual(messages.last?["role"] as? String, "tool")
        XCTAssertEqual(messages.last?["tool_call_id"] as? String, "call-1")
    }

    func testKimiCodeUsesTheOpenAICompatibleCodingEndpoint() throws {
        let baseURL = URL(string: "https://api.kimi.com/coding/v1")!
        let configuration = ProviderConfiguration(
            provider: .kimiCode,
            endpoint: ProviderID.kimiCode.messageEndpoint(for: baseURL),
            model: "kimi-for-coding",
            credentialID: "kimi-code-api-key"
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["kimi-code-api-key": "secret"]),
            transport: UnusedStreamingTransport()
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [.user("Hello")])
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.kimi.com/coding/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testKimiCodeRequestIncludesSelectedThinkingEffort() throws {
        let configuration = ProviderConfiguration(
            provider: .kimiCode,
            endpoint: URL(string: "https://api.kimi.com/coding/v1/chat/completions")!,
            model: "k3",
            credentialID: "kimi-code-api-key",
            thinkingLevel: .high
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["kimi-code-api-key": "secret"]),
            transport: UnusedStreamingTransport()
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [.user("Hello")])
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(object["reasoning_effort"] as? String, "high")
    }

    func testKimiCodeRequestUsesThinkingModeForCodingModel() throws {
        let configuration = ProviderConfiguration(
            provider: .kimiCode,
            endpoint: URL(string: "https://api.kimi.com/coding/v1/chat/completions")!,
            model: "kimi-for-coding",
            credentialID: "kimi-code-api-key",
            thinkingLevel: .off
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["kimi-code-api-key": "secret"]),
            transport: UnusedStreamingTransport()
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [.user("Hello")])
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try XCTUnwrap(object["thinking"] as? [String: Any])

        XCTAssertEqual(thinking["type"] as? String, "disabled")
        XCTAssertNil(object["reasoning_effort"])
    }

    func testKimiCodeCompositionUsesTheOpenAICompatibleAdapter() {
        let dependencies = AppDependencies(
            credentialStore: InMemoryCredentialStore(credentials: [:]),
            transport: UnusedStreamingTransport(),
            modelCatalog: URLSessionModelCatalog()
        )
        let configuration = ProviderConfiguration(
            provider: .kimiCode,
            endpoint: URL(string: "https://api.kimi.com/coding/v1/chat/completions")!,
            model: "kimi-for-coding",
            credentialID: "kimi-code-api-key"
        )

        XCTAssertTrue(dependencies.makeProvider(for: configuration) is OpenAICompatibleAdapter)
    }

    func testOpenAIAdapterWaitsThroughReasoningBeforeVisibleText() async throws {
        let configuration = ProviderConfiguration(
            provider: .kimiCode,
            endpoint: URL(string: "https://api.kimi.com/coding/v1/chat/completions")!,
            model: "kimi-for-coding",
            credentialID: "kimi-code-api-key"
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["kimi-code-api-key": "secret"]),
            transport: FixtureStreamingTransport(
                statusCode: 200,
                body: "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"thinking\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"answer\"}}]}\n\ndata: [DONE]\n\n"
            )
        )

        var events: [ProviderStreamEvent] = []
        for try await event in adapter.stream(for: ProviderRequest(messages: [.user("Hello")])) {
            events.append(event)
        }

        XCTAssertEqual(
            events,
            [
                .responseStarted,
                .continuationDelta(
                    ProviderContinuationDelta(
                        provider: .kimiCode,
                        id: "reasoning",
                        kind: "reasoning",
                        field: "text",
                        value: "thinking",
                        operation: .append
                    )
                ),
                .textDelta("answer"),
                .responseEnded,
            ]
        )
    }

    func testAnthropicRequestUsesUmansAuthenticationAndMessagesShape() throws {
        let configuration = ProviderConfiguration(
            provider: .umans,
            endpoint: URL(string: "https://api.code.umans.ai/v1/messages")!,
            model: "umans-coder",
            credentialID: "umans-api-key"
        )
        let adapter = AnthropicMessagesAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["umans-api-key": "secret"]),
            transport: UnusedStreamingTransport()
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [.system("Be concise."), .user("Hello")])
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "umans-coder")
        XCTAssertEqual(object["system"] as? String, "Be concise.")
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual((object["messages"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["messages"] as? [[String: Any]])?.first?["role"] as? String, "user")
    }

    func testAnthropicRequestPreservesThinkingBlockMetadata() throws {
        let configuration = ProviderConfiguration(
            provider: .umans,
            endpoint: URL(string: "https://api.code.umans.ai/v1/messages")!,
            model: "umans-coder",
            credentialID: "umans-api-key"
        )
        let adapter = AnthropicMessagesAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["umans-api-key": "secret"]),
            transport: UnusedStreamingTransport()
        )
        let continuation = ProviderContinuation(
            provider: .umans,
            id: "block-0",
            kind: "reasoning",
            fields: ["thinking": "plan", "signature": "opaque"]
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(messages: [.assistant("answer", continuations: [continuation])])
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "thinking")
        XCTAssertEqual(content.first?["thinking"] as? String, "plan")
        XCTAssertEqual(content.first?["signature"] as? String, "opaque")
        XCTAssertEqual(content.last?["type"] as? String, "text")
        XCTAssertEqual(content.last?["text"] as? String, "answer")
    }

    func testAnthropicRequestPreservesToolsAndToolResults() throws {
        let configuration = ProviderConfiguration(
            provider: .umans,
            endpoint: URL(string: "https://api.code.umans.ai/v1/messages")!,
            model: "umans-coder",
            credentialID: "umans-api-key"
        )
        let adapter = AnthropicMessagesAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["umans-api-key": "secret"]),
            transport: UnusedStreamingTransport()
        )
        let tool = ProviderToolDefinition(
            name: "current_time",
            description: "Returns the current time.",
            inputSchema: "{\"type\":\"object\",\"properties\":{}}"
        )
        let call = ProviderToolCall(
            id: "toolu_1",
            name: "current_time",
            arguments: "{}",
            isComplete: true
        )

        let request = try adapter.makeRequest(
            for: ProviderRequest(
                messages: [
                    .assistant("", toolCalls: [call]),
                    .tool("1970-01-01T00:00:00Z", callID: "toolu_1"),
                ],
                tools: [tool]
            )
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        let toolDefinition = try XCTUnwrap(tools.first)
        let inputSchema = try XCTUnwrap(toolDefinition["input_schema"] as? [String: Any])
        XCTAssertEqual(toolDefinition["name"] as? String, "current_time")
        XCTAssertEqual(inputSchema["type"] as? String, "object")

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let assistantContent = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.first?["type"] as? String, "tool_use")
        XCTAssertEqual(assistantContent.first?["id"] as? String, "toolu_1")
        XCTAssertEqual(assistantContent.first?["name"] as? String, "current_time")
        let resultContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(resultContent.first?["type"] as? String, "tool_result")
        XCTAssertEqual(resultContent.first?["tool_use_id"] as? String, "toolu_1")
        XCTAssertEqual(resultContent.first?["content"] as? String, "1970-01-01T00:00:00Z")
    }

    func testAnthropicAdapterTranslatesStreamingEvents() async throws {
        let configuration = ProviderConfiguration(
            provider: .umans,
            endpoint: URL(string: "https://api.code.umans.ai/v1/messages")!,
            model: "umans-coder",
            credentialID: "umans-api-key"
        )
        let adapter = AnthropicMessagesAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["umans-api-key": "secret"]),
            transport: FixtureStreamingTransport(
                statusCode: 200,
                body: "data: {\"type\":\"message_start\"}\n\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
            )
        )

        var events: [ProviderStreamEvent] = []
        for try await event in adapter.stream(for: ProviderRequest(messages: [.user("Hello")])) {
            events.append(event)
        }

        XCTAssertEqual(events, [.responseStarted, .textDelta("Hi"), .responseEnded])
    }

    func testAnthropicAdapterTranslatesStreamedToolUse() async throws {
        let configuration = ProviderConfiguration(
            provider: .umans,
            endpoint: URL(string: "https://api.code.umans.ai/v1/messages")!,
            model: "umans-coder",
            credentialID: "umans-api-key"
        )
        let adapter = AnthropicMessagesAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["umans-api-key": "secret"]),
            transport: FixtureStreamingTransport(
                statusCode: 200,
                body: "data: {\"type\":\"message_start\"}\n\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"current_time\",\"input\":{}}}\n\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\"}}\n\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"}\"}}\n\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
            )
        )

        var events: [ProviderStreamEvent] = []
        for try await event in adapter.stream(for: ProviderRequest(messages: [.user("What time is it?")])) {
            events.append(event)
        }

        XCTAssertEqual(
            events,
            [
                .responseStarted,
                .toolCallDelta(
                    ProviderToolCallDelta(
                        provider: .umans,
                        id: "toolu_1",
                        name: "current_time",
                        arguments: nil
                    )
                ),
                .toolCallDelta(
                    ProviderToolCallDelta(
                        provider: .umans,
                        id: "toolu_1",
                        name: nil,
                        arguments: "{"
                    )
                ),
                .toolCallDelta(
                    ProviderToolCallDelta(
                        provider: .umans,
                        id: "toolu_1",
                        name: nil,
                        arguments: "}"
                    )
                ),
                .finish(reason: "tool_use"),
                .responseEnded,
            ]
        )
    }

    func testAnthropicAdapterCompletesWhenStreamClosesAfterText() async throws {
        let configuration = ProviderConfiguration(
            provider: .umans,
            endpoint: URL(string: "https://api.code.umans.ai/v1/messages")!,
            model: "umans-coder",
            credentialID: "umans-api-key"
        )
        let adapter = AnthropicMessagesAdapter(
            configuration: configuration,
            credentialStore: InMemoryCredentialStore(credentials: ["umans-api-key": "secret"]),
            transport: FixtureStreamingTransport(
                statusCode: 200,
                body: "data: {\"type\":\"message_start\"}\n\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\n"
            )
        )

        var events: [ProviderStreamEvent] = []
        for try await event in adapter.stream(for: ProviderRequest(messages: [.user("Hello")])) {
            events.append(event)
        }

        XCTAssertEqual(events, [.responseStarted, .textDelta("Hi"), .responseEnded])
    }
}

private struct UnusedStreamingTransport: StreamingTransport {
    func response(for request: URLRequest) async throws -> StreamingResponse {
        fatalError("request construction test must not execute the transport")
    }
}

private struct FixtureStreamingTransport: StreamingTransport {
    let statusCode: Int
    let body: String

    func response(for request: URLRequest) async throws -> StreamingResponse {
        let bytes = Array(body.utf8)
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in bytes {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        return StreamingResponse(statusCode: statusCode, bytes: stream)
    }
}

private final class StreamingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
