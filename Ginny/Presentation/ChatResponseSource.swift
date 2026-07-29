import Combine
import Foundation
import SwiftStreamingMarkdown

final class ChatResponseSource: StreamedMarkdownSource, ObservableObject, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]
    private var latestSnapshot = ""
    private var isFinished = false

    var text: AsyncStream<String> {
        let stream = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()

        lock.lock()
        let finished = isFinished
        if !finished {
            continuations[id] = stream.continuation
            if !latestSnapshot.isEmpty {
                stream.continuation.yield(latestSnapshot)
            }
        }
        lock.unlock()

        stream.continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(id)
        }

        if finished {
            stream.continuation.finish()
        }

        return stream.stream
    }

    func yield(_ snapshot: String) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        latestSnapshot = snapshot
        let activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield(snapshot)
        }
    }

    func replayLatest() {
        lock.lock()
        let snapshot = latestSnapshot
        let activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield(snapshot)
        }
    }

    func finish() {
        lock.lock()
        isFinished = true
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
