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
        let parser = OpenAICompatibleStreamParser()

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

    func testOpenAIStreamParserMapsProviderError() {
        let parser = OpenAICompatibleStreamParser()

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
        let parser = AnthropicMessagesStreamParser()

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

    func testAnthropicStreamParserMapsProviderError() {
        let parser = AnthropicMessagesStreamParser()

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

        XCTAssertEqual(events, [.responseStarted, .textDelta("answer"), .responseEnded])
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
