import Combine
import SwiftStreamingMarkdown

@MainActor
final class ChatResponseSource: StreamedMarkdownSource, ObservableObject {
    let text: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation

    init() {
        let stream = AsyncStream<String>.makeStream()
        text = stream.stream
        continuation = stream.continuation
    }

    func yield(_ snapshot: String) {
        continuation.yield(snapshot)
    }

    func finish() {
        continuation.finish()
    }
}
