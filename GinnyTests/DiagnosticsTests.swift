import Foundation
import XCTest
@testable import Ginny

final class DiagnosticsTests: XCTestCase {
    func testOperationIdentityIsStableAndCodable() throws {
        let operation = OperationIdentity(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "provider.stream"
        )

        let data = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(OperationIdentity.self, from: data)

        XCTAssertEqual(decoded, operation)
    }

    func testProviderFailuresCarryRecoveryAndRetryContract() {
        let operation = OperationIdentity(name: "provider.stream")
        let rateLimit = ProviderError.httpStatus(429, message: "slow down")
        let authentication = ProviderError.httpStatus(401, message: nil)

        let rateLimitFailure = rateLimit.asOperationFailure(operation: operation)
        let authenticationFailure = authentication.asOperationFailure(operation: operation)

        XCTAssertEqual(rateLimitFailure.category, .rateLimit)
        XCTAssertEqual(rateLimitFailure.retryability, .afterDelay)
        XCTAssertEqual(rateLimitFailure.recoverySuggestion, .waitAndRetry)
        XCTAssertEqual(rateLimitFailure.operation, operation)
        XCTAssertEqual(authenticationFailure.category, .authentication)
        XCTAssertEqual(authenticationFailure.retryability, .userAction)
        XCTAssertEqual(authenticationFailure.recoverySuggestion, .checkCredentials)
    }

    func testDiagnosticsSpanReturnsWorkResultAndDoesNotStoreContent() throws {
        let operation = OperationIdentity(name: "search.flush")

        let result = GinnyDiagnostics.withSpan(operation) {
            42
        }

        XCTAssertEqual(result, 42)
    }
}
