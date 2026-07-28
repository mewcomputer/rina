import Foundation
import XCTest
@testable import Ginny

@MainActor
final class ChatSessionTests: XCTestCase {
    func testSessionPreservesCompletedUserAndAssistantMessages() async {
        let provider = StubProvider(events: [
            .responseStarted,
            .textDelta("Hello"),
            .textDelta(" back."),
            .finish(reason: "stop"),
            .responseEnded,
        ])
        let session = ChatSession(provider: provider)

        await session.send("Hi")

        XCTAssertEqual(session.conversation.generationState, .completed)
        XCTAssertEqual(session.conversation.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(session.conversation.messages[0].blocks[0].payload, "Hi")
        XCTAssertEqual(session.conversation.messages[1].blocks[0].payload, "Hello back.")
        XCTAssertTrue(session.conversation.messages[1].blocks[0].isComplete)
    }

    func testSessionPreservesPartialContentWhenProviderFails() async {
        let provider = StubProvider(
            events: [.responseStarted, .textDelta("Partial")],
            failure: ProviderError.remote(message: "connection lost")
        )
        let session = ChatSession(provider: provider)

        await session.send("Hi")

        XCTAssertEqual(session.conversation.generationState, .failed)
        XCTAssertEqual(session.conversation.messages[1].blocks[0].payload, "Partial")
        XCTAssertFalse(session.conversation.messages[1].blocks[0].isComplete)
        XCTAssertEqual(session.errorMessage, "connection lost")
    }

    func testSessionConsumesOpenAICompatibleStreamingAdapter() async {
        let adapter = OpenAICompatibleAdapter(
            configuration: ProviderConfiguration(
                endpoint: URL(string: "https://example.com/v1/chat/completions")!,
                model: "fixture-model",
                credentialID: "primary"
            ),
            credentialStore: InMemoryCredentialStore(credentials: ["primary": "secret"]),
            transport: FixtureStreamingTransport(
                statusCode: 200,
                body: "data: {\"choices\":[{\"delta\":{\"content\":\"Hello **there**\"}}]}\n\ndata: [DONE]\n\n"
            )
        )
        let session = ChatSession(provider: adapter)

        await session.send("Hello")

        XCTAssertEqual(session.conversation.generationState, .completed)
        XCTAssertEqual(session.streamingText, "Hello **there**")
        XCTAssertEqual(
            session.conversation.messages.last?.blocks.first?.payload,
            "Hello **there**"
        )
    }
}

private struct StubProvider: ProviderAdapter {
    let events: [ProviderStreamEvent]
    let failure: Error?

    init(events: [ProviderStreamEvent], failure: Error? = nil) {
        self.events = events
        self.failure = failure
    }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.finish()
            }
        }
    }
}

private struct FixtureStreamingTransport: StreamingTransport {
    let statusCode: Int
    let body: String

    func response(for request: URLRequest) async throws -> StreamingResponse {
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in body.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        return StreamingResponse(statusCode: statusCode, bytes: stream)
    }
}
