import Foundation
import XCTest
@testable import Ginny

final class CodexOAuthTests: XCTestCase {
    func testCallbackUsesCodexLoopbackPort() {
        XCTAssertEqual(CodexOAuthService.callbackURL.port, 1455)
        XCTAssertEqual(CodexOAuthService.callbackPort, 1455)
        XCTAssertEqual(CodexOAuthService.callbackURL.path, "/auth/callback")
        XCTAssertEqual(
            CodexOAuthService.appCallbackURL.absoluteString,
            "computer.mew.rina://codex/oauth/callback"
        )
    }

    func testExpiredAccessTokenRefreshesAndPersistsRotatedTokens() async throws {
        let credentials = MutableCredentialStore()
        let expired = CodexOAuthTokens(
            accessToken: "expired-access",
            refreshToken: "old-refresh",
            idToken: "old-id",
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        credentials.values[CodexOAuthService.credentialID] = String(
            data: try JSONEncoder().encode(expired),
            encoding: .utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexOAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)
        CodexOAuthURLProtocol.responseData = Data(
            """
            {
              "access_token": "fresh-access",
              "refresh_token": "new-refresh",
              "id_token": "new-id",
              "expires_in": 3600
            }
            """.utf8
        )
        CodexOAuthURLProtocol.statusCode = 200

        let service = CodexOAuthService(
            credentialStore: credentials,
            session: session,
            issuer: URL(string: "https://auth.example")!
        )

        let accessToken = try await service.accessToken()

        XCTAssertEqual(accessToken, "fresh-access")
        XCTAssertEqual(CodexOAuthURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(
            CodexOAuthURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        let saved = try XCTUnwrap(credentials.values[CodexOAuthService.credentialID])
        let refreshed = try JSONDecoder().decode(CodexOAuthTokens.self, from: Data(saved.utf8))
        XCTAssertEqual(refreshed.refreshToken, "new-refresh")
        XCTAssertGreaterThan(refreshed.expiresAt ?? .distantPast, Date())
    }

    func testRefreshAuthenticationFailureClearsStoredTokens() async throws {
        let credentials = MutableCredentialStore()
        let expired = CodexOAuthTokens(
            accessToken: "expired-access",
            refreshToken: "old-refresh",
            idToken: "old-id",
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        credentials.values[CodexOAuthService.credentialID] = String(
            data: try JSONEncoder().encode(expired),
            encoding: .utf8
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexOAuthURLProtocol.self]
        CodexOAuthURLProtocol.statusCode = 401
        CodexOAuthURLProtocol.responseData = Data("{\"error_description\":\"invalid_grant\"}".utf8)
        let service = CodexOAuthService(
            credentialStore: credentials,
            session: URLSession(configuration: configuration),
            issuer: URL(string: "https://auth.example")!
        )

        do {
            _ = try await service.accessToken()
            XCTFail("Expected refresh authentication failure")
        } catch let error as CodexOAuthError {
            XCTAssertEqual(error, .signedOut)
        }

        XCTAssertNil(credentials.values[CodexOAuthService.credentialID])
        let isSignedIn = await service.isSignedIn()
        XCTAssertFalse(isSignedIn)
    }

    func testSignInUsesAppCallbackRelayAndPersistsTokens() async throws {
        let credentials = MutableCredentialStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexOAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)
        CodexOAuthURLProtocol.responseData = Data(
            """
            {
              "access_token": "access",
              "refresh_token": "refresh",
              "id_token": "id",
              "expires_in": 3600
            }
            """.utf8
        )
        CodexOAuthURLProtocol.statusCode = 200

        let service = CodexOAuthService(
            credentialStore: credentials,
            session: session,
            issuer: URL(string: "https://auth.example")!,
            userAuthenticator: { url, scheme in
                XCTAssertEqual(scheme, CodexOAuthService.appCallbackURL.scheme)
                let state = try XCTUnwrap(
                    URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "state" })?
                        .value
                )
                return try XCTUnwrap(
                    URL(string: "\(CodexOAuthService.appCallbackURL.absoluteString)?code=code&state=\(state)")
                )
            }
        )

        try await service.signIn()

        let isSignedIn = await service.isSignedIn()
        XCTAssertTrue(isSignedIn)
        XCTAssertNotNil(credentials.values[CodexOAuthService.credentialID])
    }

    func testMissingTokensRequireSignIn() async {
        let service = CodexOAuthService(credentialStore: MutableCredentialStore())

        do {
            _ = try await service.accessToken()
            XCTFail("Expected signed-out service to reject access")
        } catch let error as CodexOAuthError {
            XCTAssertEqual(error, .signedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoopbackRequestBufferWaitsForCompleteHeaders() {
        var buffer = CodexLoopbackRequestBuffer()

        XCTAssertNil(buffer.append(Data("GET /auth/callback?code=one HTTP/1.1\r\nHost: localhost\r\n".utf8), isComplete: false))
        XCTAssertEqual(
            buffer.append(Data("\r\n".utf8), isComplete: false),
            Data("GET /auth/callback?code=one HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        )
    }
}

private final class MutableCredentialStore: CredentialStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func credential(for identifier: String) throws -> String? {
        values[identifier]
    }

    func save(_ credential: String, for identifier: String) throws {
        values[identifier] = credential
    }

    func deleteCredential(for identifier: String) throws {
        values.removeValue(forKey: identifier)
    }
}

private final class CodexOAuthURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
