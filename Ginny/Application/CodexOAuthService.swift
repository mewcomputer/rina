import AuthenticationServices
import CryptoKit
import Foundation
import Network
import OAuth4Swift

struct CodexOAuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresAt: Date?
}

enum CodexOAuthError: Error, Equatable, Sendable, LocalizedError {
    case signedOut
    case cancelled
    case invalidCallback
    case callbackPortUnavailable
    case invalidTokenResponse
    case httpStatus(Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .signedOut:
            "Codex is not signed in."
        case .cancelled:
            "Codex sign-in was cancelled."
        case .invalidCallback:
            "Codex sign-in returned an invalid callback."
        case .callbackPortUnavailable:
            "Codex sign-in could not start because local callback port 1455 is unavailable."
        case .invalidTokenResponse:
            "Codex sign-in returned an invalid token response."
        case let .httpStatus(status, message):
            if let message, !message.isEmpty {
                "Codex sign-in failed (HTTP \(status)): \(message)"
            } else {
                "Codex sign-in failed (HTTP \(status))."
            }
        }
    }
}

/// ChatGPT OAuth for the Codex provider follows the flow used by the Codex
/// CLI. It targets the Codex ChatGPT backend, which is separate from the
/// public OpenAI API and may change independently.
actor CodexOAuthService {
    static let credentialID = "codex.oauth.tokens"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let officialBackendHost = "chatgpt.com"
    static let issuer = URL(string: "https://auth.openai.com")!
    static let callbackURL = URL(string: "http://localhost:1455/auth/callback")!
    static let callbackPort: UInt16 = 1455
    static let appCallbackURL = URL(string: "computer.mew.rina://codex/oauth/callback")!
    static let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"

    static func isOfficialBackendURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == officialBackendHost
            && url.port == nil
            && normalizedBackendPath(url) == "/backend-api/codex"
    }

    static func isOfficialBackendEndpointURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == officialBackendHost
            && url.port == nil
            && normalizedBackendPath(url) == "/backend-api/codex/responses"
    }

    private static func normalizedBackendPath(_ url: URL) -> String {
        url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
    }

    private let credentialStore: any CredentialStore
    private let session: URLSession
    private let authorizeURL: URL
    private let tokenURL: URL
    private let userAuthenticator: UserAuthenticator
    private var tokens: CodexOAuthTokens?

    init(
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        session: URLSession = .shared,
        issuer: URL = CodexOAuthService.issuer,
        userAuthenticator: @escaping UserAuthenticator = ASWebAuthenticationSession.userAuthenticator()
    ) {
        self.credentialStore = credentialStore
        self.session = session
        authorizeURL = issuer.appendingPathComponent("oauth/authorize")
        tokenURL = issuer.appendingPathComponent("oauth/token")
        self.userAuthenticator = userAuthenticator
        if let stored = try? credentialStore.credential(for: Self.credentialID),
           let data = stored.data(using: .utf8),
           let tokens = try? JSONDecoder().decode(CodexOAuthTokens.self, from: data)
        {
            self.tokens = tokens
        } else {
            tokens = nil
        }
    }

    func isSignedIn() -> Bool {
        tokens != nil
    }

    func signIn() async throws {
        let verifier = Self.makeCodeVerifier()
        let state = Self.makeRandomString()
        let challenge = Self.makeCodeChallenge(verifier: verifier)
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "codex_cli_rs"),
        ]
        guard let url = components?.url else {
            throw CodexOAuthError.invalidCallback
        }

        let callbackServer: CodexLoopbackCallbackServer
        do {
            callbackServer = try CodexLoopbackCallbackServer(port: Self.callbackPort)
            try await callbackServer.start()
        } catch {
            throw CodexOAuthError.callbackPortUnavailable
        }
        defer { callbackServer.stop() }

        let callback: URL
        do {
            callback = try await userAuthenticator(url, Self.appCallbackURL.scheme!)
        } catch is CancellationError {
            throw CodexOAuthError.cancelled
        } catch {
            throw error
        }

        guard let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw CodexOAuthError.invalidCallback
        }
        if callbackComponents.queryItems?.first(where: { $0.name == "error" })?.value != nil {
            throw CodexOAuthError.cancelled
        }
        guard callback.scheme == Self.appCallbackURL.scheme,
              callback.host == Self.appCallbackURL.host,
              callback.path == Self.appCallbackURL.path,
              callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw CodexOAuthError.invalidCallback
        }

        let tokenResponse = try await exchange(
            grantType: "authorization_code",
            code: code,
            verifier: verifier
        )
        guard let refreshToken = tokenResponse.refreshToken else {
            throw CodexOAuthError.invalidTokenResponse
        }
        let newTokens = CodexOAuthTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken,
            idToken: tokenResponse.idToken,
            expiresAt: tokenResponse.expiresAt
        )
        try persist(newTokens)
        tokens = newTokens
    }

    func accessToken() async throws -> String {
        guard let tokens else {
            throw CodexOAuthError.signedOut
        }
        guard let expiresAt = tokens.expiresAt,
              expiresAt <= Date().addingTimeInterval(60) else {
            return tokens.accessToken
        }
        guard let refreshToken = tokens.refreshToken else {
            throw CodexOAuthError.signedOut
        }

        let response: CodexOAuthTokenResponse
        do {
            response = try await exchange(
                grantType: "refresh_token",
                code: refreshToken,
                verifier: nil
            )
        } catch let CodexOAuthError.httpStatus(status, _) where [400, 401, 403].contains(status) {
            signOut()
            throw CodexOAuthError.signedOut
        }
        let refreshed = CodexOAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            idToken: response.idToken ?? tokens.idToken,
            expiresAt: response.expiresAt
        )
        try persist(refreshed)
        self.tokens = refreshed
        return refreshed.accessToken
    }

    func signOut() {
        tokens = nil
        try? credentialStore.deleteCredential(for: Self.credentialID)
    }

    private func exchange(
        grantType: String,
        code: String,
        verifier: String?
    ) async throws -> CodexOAuthTokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: grantType),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(
                name: grantType == "refresh_token" ? "refresh_token" : "code",
                value: code
            ),
        ]
        if let verifier {
            components.queryItems?.append(
                URLQueryItem(name: "redirect_uri", value: Self.callbackURL.absoluteString)
            )
            components.queryItems?.append(
                URLQueryItem(name: "code_verifier", value: verifier)
            )
        }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CodexOAuthError.invalidTokenResponse
        }
        guard 200..<300 ~= response.statusCode else {
            let message = try? JSONDecoder().decode(
                CodexOAuthErrorResponse.self,
                from: data
            ).message
            throw CodexOAuthError.httpStatus(response.statusCode, message: message)
        }
        return try JSONDecoder().decode(CodexOAuthTokenResponse.self, from: data)
    }

    private func persist(_ tokens: CodexOAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        guard let value = String(data: data, encoding: .utf8) else {
            throw CodexOAuthError.invalidTokenResponse
        }
        try credentialStore.save(value, for: Self.credentialID)
    }

    private static func makeCodeVerifier() -> String {
        makeRandomString(byteCount: 32)
    }

    private static func makeRandomString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private static func makeCodeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

struct CodexLoopbackRequestBuffer: Equatable, Sendable {
    private var data = Data()

    mutating func append(_ chunk: Data, isComplete: Bool) -> Data? {
        data.append(chunk)
        let headerTerminator = Data("\r\n\r\n".utf8)
        guard data.range(of: headerTerminator) != nil
                || isComplete
                || data.count >= 16 * 1024
        else {
            return nil
        }
        return data
    }
}

private final class CodexLoopbackCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let port: UInt16
    private let queue = DispatchQueue(label: "fm.teal.ginny.codex-oauth-callback")

    init(port: UInt16) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw CodexOAuthError.callbackPortUnavailable
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: endpointPort
        )
        self.port = port
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: self.queue)
            Self.receiveRequest(on: connection, buffer: CodexLoopbackRequestBuffer(), port: self.port)
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: CodexOAuthError.callbackPortUnavailable)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func respond(to connection: NWConnection, request: Data?, port: UInt16) {
        let response: Data
        if let redirectURL = redirectURL(for: request, port: port) {
            response = Data(
                "HTTP/1.1 302 Found\r\nLocation: \(redirectURL.absoluteString)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8
            )
        } else {
            let body = Data("Not found".utf8)
            response = Data(
                "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8
            ) + body
        }
        connection.send(
            content: response,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private static func receiveRequest(
        on connection: NWConnection,
        buffer: CodexLoopbackRequestBuffer,
        port: UInt16
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16 * 1024
        ) { data, _, isComplete, error in
            var buffer = buffer
            guard error == nil else {
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                if isComplete {
                    respond(to: connection, request: nil, port: port)
                } else {
                    connection.cancel()
                }
                return
            }
            guard let request = buffer.append(data, isComplete: isComplete) else {
                receiveRequest(on: connection, buffer: buffer, port: port)
                return
            }
            respond(to: connection, request: request, port: port)
        }
    }

    private static func redirectURL(for request: Data?, port: UInt16) -> URL? {
        guard let request,
              let requestLine = String(data: request, encoding: .utf8)?
                .components(separatedBy: "\r\n")
                .first,
              let target = requestLine.split(separator: " ").dropFirst().first,
              let sourceURL = URL(string: "http://localhost:\(port)\(target)"),
              let sourceComponents = URLComponents(
                url: sourceURL,
                resolvingAgainstBaseURL: false
              ),
              sourceComponents.path == CodexOAuthService.callbackURL.path,
              var callbackComponents = URLComponents(
                url: CodexOAuthService.appCallbackURL,
                resolvingAgainstBaseURL: false
              )
        else {
            return nil
        }

        callbackComponents.queryItems = sourceComponents.queryItems
        return callbackComponents.url
    }
}

private struct CodexOAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresAt: Date?

    private let expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
    }
}

private struct CodexOAuthErrorResponse: Decodable, Sendable {
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case message = "error_description"
    }
}
