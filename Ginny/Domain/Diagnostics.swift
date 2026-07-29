import Foundation
import OSLog

struct OperationIdentity: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

enum OperationFailureCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case configuration
    case authentication
    case rateLimit
    case remote
    case transport
    case decoding
    case persistence
    case cancellation
    case unknown
}

enum OperationRetryability: String, Codable, CaseIterable, Equatable, Sendable {
    case never
    case safe
    case afterDelay
    case userAction
}

enum RecoverySuggestion: String, Codable, CaseIterable, Equatable, Sendable {
    case checkConfiguration
    case checkCredentials
    case waitAndRetry
    case retry
    case tryAgain
    case none
}

struct OperationFailure: Error, Codable, Equatable, Sendable {
    let category: OperationFailureCategory
    let retryability: OperationRetryability
    let recoverySuggestion: RecoverySuggestion
    let diagnosticMessage: String?
    let operation: OperationIdentity

    init(
        category: OperationFailureCategory,
        retryability: OperationRetryability,
        recoverySuggestion: RecoverySuggestion,
        diagnosticMessage: String? = nil,
        operation: OperationIdentity
    ) {
        self.category = category
        self.retryability = retryability
        self.recoverySuggestion = recoverySuggestion
        self.diagnosticMessage = diagnosticMessage
        self.operation = operation
    }
}

extension ProviderError {
    func asOperationFailure(operation: OperationIdentity) -> OperationFailure {
        switch self {
        case .invalidConfiguration(let message):
            OperationFailure(
                category: .configuration,
                retryability: .never,
                recoverySuggestion: .checkConfiguration,
                diagnosticMessage: message,
                operation: operation
            )
        case .missingCredential:
            OperationFailure(
                category: .authentication,
                retryability: .userAction,
                recoverySuggestion: .checkCredentials,
                operation: operation
            )
        case .invalidResponse, .malformedEvent:
            OperationFailure(
                category: .decoding,
                retryability: .never,
                recoverySuggestion: .tryAgain,
                operation: operation
            )
        case .httpStatus(let status, let message):
            if status == 401 || status == 403 {
                OperationFailure(
                    category: .authentication,
                    retryability: .userAction,
                    recoverySuggestion: .checkCredentials,
                    diagnosticMessage: message,
                    operation: operation
                )
            } else if status == 429 {
                OperationFailure(
                    category: .rateLimit,
                    retryability: .afterDelay,
                    recoverySuggestion: .waitAndRetry,
                    diagnosticMessage: message,
                    operation: operation
                )
            } else if status >= 500 {
                OperationFailure(
                    category: .remote,
                    retryability: .safe,
                    recoverySuggestion: .retry,
                    diagnosticMessage: message,
                    operation: operation
                )
            } else {
                OperationFailure(
                    category: .remote,
                    retryability: .never,
                    recoverySuggestion: .tryAgain,
                    diagnosticMessage: message,
                    operation: operation
                )
            }
        case .remote(let message):
            OperationFailure(
                category: .remote,
                retryability: .never,
                recoverySuggestion: .tryAgain,
                diagnosticMessage: message,
                operation: operation
            )
        }
    }
}

enum GinnyDiagnostics {
    static let log = Logger(subsystem: "fm.teal.ginny", category: "operations")
    static let signposter = OSSignposter(subsystem: "fm.teal.ginny", category: "operations")

    @discardableResult
    static func withSpan<Result>(
        _ operation: OperationIdentity,
        _ work: () throws -> Result
    ) rethrows -> Result {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("operation", id: signpostID)
        let startedAt = Date()
        log.debug("operation started \(operation.name, privacy: .public) \(operation.id.uuidString, privacy: .public)")
        defer {
            let duration = Date().timeIntervalSince(startedAt)
            signposter.endInterval("operation", state)
            log.debug("operation finished \(operation.name, privacy: .public) \(operation.id.uuidString, privacy: .public) duration=\(duration, privacy: .public)")
        }
        return try work()
    }

    @discardableResult
    static func withSpan<Result>(
        _ operation: OperationIdentity,
        _ work: () async throws -> Result
    ) async rethrows -> Result {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("operation", id: signpostID)
        let startedAt = Date()
        log.debug("operation started \(operation.name, privacy: .public) \(operation.id.uuidString, privacy: .public)")
        defer {
            let duration = Date().timeIntervalSince(startedAt)
            signposter.endInterval("operation", state)
            log.debug("operation finished \(operation.name, privacy: .public) \(operation.id.uuidString, privacy: .public) duration=\(duration, privacy: .public)")
        }
        return try await work()
    }
}
