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
