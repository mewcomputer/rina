import Foundation
import XCTest
@testable import Ginny

@MainActor
final class ChatSessionTests: XCTestCase {
    func testSessionAddsArtefactCapabilityInstructionsToProviderRequest() async throws {
        let provider = RecordingContinuationProvider()
        let session = ChatSession(provider: provider)

        await session.send("Make a small web preview and save it.")

        let request = try XCTUnwrap(provider.recorder.requests.first)
        let systemMessage = try XCTUnwrap(request.messages.first)
        XCTAssertEqual(systemMessage.role, .system)
        XCTAssertTrue(systemMessage.content.contains("artefact"))
        XCTAssertTrue(systemMessage.content.contains("immutable revisions"))
        XCTAssertTrue(systemMessage.content.contains("inlineWeb"))
        XCTAssertTrue(systemMessage.content.contains("discover_skills"))
        XCTAssertTrue(systemMessage.content.contains("create_artefact"))
    }

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

    func testSessionPublishesStreamingReasoningSnapshot() async {
        let provider = StubProvider(events: [
            .responseStarted,
            .continuationDelta(
                ProviderContinuationDelta(
                    provider: .kimiCode,
                    id: "reasoning",
                    kind: "reasoning",
                    field: "text",
                    value: "plan",
                    operation: .append
                )
            ),
            .continuationDelta(
                ProviderContinuationDelta(
                    provider: .kimiCode,
                    id: "reasoning",
                    kind: "reasoning",
                    field: "text",
                    value: " then answer",
                    operation: .append
                )
            ),
            .textDelta("Done"),
            .responseEnded,
        ])
        let session = ChatSession(provider: provider)

        await session.send("Hi")

        XCTAssertEqual(session.streamingReasoningText, "plan then answer")
    }

    func testSessionCanAttachArtefactReferenceToAnAssistantMessage() {
        let message = Message.assistant("Saved answer")
        let conversation = Conversation(messages: [message], generationState: .completed)
        let session = ChatSession(conversation: conversation)
        let artefact = Artefact(title: "Saved answer", kind: .document)
        var artefactWithRevision = artefact
        let revisionID = artefactWithRevision.checkpoint(source: "Saved answer")

        session.attachArtefact(artefactWithRevision, to: message.id)

        XCTAssertEqual(
            session.conversation.messages[0].blocks.last?.kind,
            .artefactReference
        )
        XCTAssertEqual(
            session.conversation.messages[0].blocks.last?.attributes["revisionID"],
            revisionID.rawValue.uuidString
        )
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

    func testSessionPersistsPartialContentDuringStreaming() async {
        let provider = BlockingProvider()
        var snapshots: [Conversation] = []
        let session = ChatSession(
            provider: provider,
            persistence: { snapshots.append($0) }
        )
        let task = Task { @MainActor in
            await session.send("Hi")
        }

        for _ in 0..<100 where session.streamingText != "Partial" {
            await Task.yield()
        }

        XCTAssertTrue(
            snapshots.contains {
                $0.generationState == .streaming
                    && $0.messages.last?.blocks.first?.payload == "Partial"
            }
        )

        session.cancel()
        await task.value
    }

    func testCancellingGenerationStopsTheProviderAndPreservesPartialContent() async {
        let provider = BlockingProvider()
        let session = ChatSession(provider: provider)
        let task = Task { @MainActor in
            await session.send("Hi")
        }

        for _ in 0..<100 where session.streamingText != "Partial" {
            await Task.yield()
        }

        XCTAssertEqual(session.conversation.generationState, .streaming)
        session.cancel()
        await task.value

        XCTAssertEqual(session.conversation.generationState, .cancelled)
        XCTAssertEqual(session.conversation.messages[1].blocks[0].payload, "Partial")
        XCTAssertFalse(session.conversation.messages[1].blocks[0].isComplete)
        let wasTerminated = await provider.terminationState.wasTerminated
        XCTAssertTrue(wasTerminated)
    }

    func testSessionExplainsRateLimitErrors() async {
        let provider = StubProvider(
            events: [],
            failure: ProviderError.httpStatus(
                429,
                message: "Too many requests. Try again later."
            )
        )
        let session = ChatSession(provider: provider)

        await session.send("Hi")

        XCTAssertEqual(
            session.errorMessage,
            "Rate limit reached. Too many requests. Try again later."
        )
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

    func testSessionPersistsAndReusesProviderContinuationMetadata() async throws {
        let provider = RecordingContinuationProvider()
        let session = ChatSession(provider: provider)

        await session.send("first")
        await session.send("second")

        let requests = provider.recorder.requests
        XCTAssertEqual(requests.count, 2)
        let assistant = try XCTUnwrap(
            requests[1].messages.first(where: { $0.role == .assistant })
        )
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(
            assistant.continuations.first?.fields["text"],
            "thinking"
        )
    }

    func testSessionExecutesReadOnlyToolAndResumesTheGeneration() async {
        let fixedDate = Date(timeIntervalSince1970: 0)
        let provider = ToolLoopProvider()
        let session = ChatSession(
            provider: provider,
            toolRegistry: ToolRegistry(tools: [CurrentTimeTool(now: { fixedDate })])
        )

        await session.send("What time is it?")

        XCTAssertEqual(session.conversation.generationState, .completed)
        XCTAssertEqual(
            session.conversation.messages.map(\.role),
            [.user, .assistant, .tool, .assistant]
        )
        XCTAssertEqual(
            session.conversation.messages[2].blocks.first?.payload,
            "1970-01-01T00:00:00Z"
        )
        XCTAssertEqual(session.conversation.messages[3].blocks.first?.payload, "Done.")
        XCTAssertEqual(session.streamingReasoningText, "initial reasoning")

        let requests = provider.recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].tools.first?.name, "current_time")
        XCTAssertEqual(requests[1].messages.last?.role, .tool)
        XCTAssertEqual(requests[1].messages.last?.toolCallID, "call-1")
    }

    func testSessionPausesForToolApprovalAndResumesAfterApproval() async {
        let provider = ApprovalLoopProvider()
        let session = ChatSession(
            provider: provider,
            toolRegistry: ToolRegistry(tools: [ApprovalRequiredSessionTool()])
        )
        let task = Task { @MainActor in
            await session.send("Run the approved tool")
        }

        for _ in 0..<100 where session.pendingToolApproval == nil {
            await Task.yield()
        }

        XCTAssertEqual(
            session.pendingToolApproval,
            ToolApprovalRequest(id: "approval-call", name: "requires_approval", arguments: "{}")
        )
        session.approvePendingTool()
        await task.value

        XCTAssertEqual(session.conversation.generationState, .completed)
        XCTAssertEqual(
            session.conversation.messages[2].blocks.first?.attributes["approvalState"],
            ToolApprovalState.approved.rawValue
        )
        XCTAssertEqual(session.conversation.messages.last?.blocks.first?.payload, "Approved.")
    }
}

private struct StubProvider: ProviderAdapter {
    let events: [ProviderStreamEvent]
    let failure: Error?

    var supportsTools: Bool { false }

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

private actor StreamTerminationState {
    private(set) var wasTerminated = false

    func markTerminated() {
        wasTerminated = true
    }
}

private final class BlockingProvider: ProviderAdapter, @unchecked Sendable {
    let terminationState = StreamTerminationState()

    var supportsTools: Bool { false }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.responseStarted)
            continuation.yield(.textDelta("Partial"))
            continuation.onTermination = { [terminationState] _ in
                Task {
                    await terminationState.markTerminated()
                }
            }
        }
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [ProviderRequest] = []

    var requests: [ProviderRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func record(_ request: ProviderRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }
}

private final class RecordingContinuationProvider: ProviderAdapter, @unchecked Sendable {
    let recorder = RequestRecorder()

    var supportsTools: Bool { false }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        recorder.record(request)

        return AsyncThrowingStream { continuation in
            continuation.yield(.responseStarted)
            continuation.yield(.continuationDelta(
                ProviderContinuationDelta(
                    provider: .kimiCode,
                    id: "reasoning",
                    kind: "reasoning",
                    field: "text",
                    value: "thinking",
                    operation: .append
                )
            ))
            continuation.yield(.textDelta("answer"))
            continuation.yield(.responseEnded)
            continuation.finish()
        }
    }
}

private final class ToolLoopProvider: ProviderAdapter, @unchecked Sendable {
    let recorder = RequestRecorder()

    var supportsTools: Bool { true }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        recorder.record(request)
        let isFirstResponse = request.messages.last?.role == .user
        let events: [ProviderStreamEvent]
        if isFirstResponse {
            events = [
                .responseStarted,
                .continuationDelta(
                    ProviderContinuationDelta(
                        provider: .openAICompatible,
                        id: "reasoning",
                        kind: "reasoning",
                        field: "text",
                        value: "initial reasoning",
                        operation: .append
                    )
                ),
                .toolCallDelta(
                    ProviderToolCallDelta(
                        provider: .openAICompatible,
                        id: "call-1",
                        name: "current_time",
                        arguments: "{"
                    )
                ),
                .toolCallDelta(
                    ProviderToolCallDelta(
                        provider: .openAICompatible,
                        id: "call-1",
                        name: nil,
                        arguments: "}"
                    )
                ),
                .finish(reason: "tool_calls"),
                .responseEnded,
            ]
        } else {
            events = [.responseStarted, .textDelta("Done."), .responseEnded]
        }

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private struct ApprovalRequiredSessionTool: GinnyTool {
    let definition = ProviderToolDefinition(
        name: "requires_approval",
        description: "A test tool requiring user approval.",
        inputSchema: "{\"type\":\"object\"}"
    )

    let approvalRequirement: ToolApprovalRequirement = .requiresApproval

    func execute(arguments: String) async throws -> String {
        "approved"
    }
}

private final class ApprovalLoopProvider: ProviderAdapter, @unchecked Sendable {
    var supportsTools: Bool { true }

    func stream(for request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let isFirstResponse = request.messages.last?.role == .user
        let events: [ProviderStreamEvent] = isFirstResponse
            ? [
                .responseStarted,
                .toolCallDelta(
                    ProviderToolCallDelta(
                        provider: .openAICompatible,
                        id: "approval-call",
                        name: "requires_approval",
                        arguments: "{}"
                    )
                ),
                .finish(reason: "tool_calls"),
                .responseEnded,
            ]
            : [.responseStarted, .textDelta("Approved."), .responseEnded]

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
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
