import Foundation

struct StreamingResponse: Sendable {
    let statusCode: Int
    let bytes: AsyncThrowingStream<UInt8, Error>
}

protocol StreamingTransport: Sendable {
    func response(for request: URLRequest) async throws -> StreamingResponse
}

struct URLSessionStreamingTransport: StreamingTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func response(for request: URLRequest) async throws -> StreamingResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            let task = Task {
                do {
                    for try await byte in bytes {
                        continuation.yield(byte)
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

        return StreamingResponse(statusCode: httpResponse.statusCode, bytes: stream)
    }
}
