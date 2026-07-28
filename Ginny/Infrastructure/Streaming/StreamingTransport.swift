import Foundation

struct StreamingResponse: Sendable {
    let statusCode: Int
    let bytes: AsyncThrowingStream<UInt8, Error>

    func data() async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
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

func providerErrorMessage(from data: Data) -> String? {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty
        {
            return message
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        if let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }
    }

    let text = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}
