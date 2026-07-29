import Foundation
import SwiftAtproto

struct AtprotoResolvedIdentity: Equatable, Sendable {
    let handle: String?
    let did: String
    let pdsURL: String
}

protocol AtprotoIdentityResolving: Sendable {
    func resolve(identifier: String) async throws -> AtprotoResolvedIdentity
}

struct GinnyAtprotoIdentityResolver: AtprotoIdentityResolving, Sendable {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func resolve(identifier: String) async throws -> AtprotoResolvedIdentity {
        do {
            let normalizedIdentifier = try AtprotoAuthService.normalizeHandle(identifier)
            let requestedHandle: Handle?
            let did: DID

            if normalizedIdentifier.lowercased().hasPrefix("did:") {
                requestedHandle = nil
                did = try DID(string: normalizedIdentifier)
            } else {
                let handle = try Handle(string: normalizedIdentifier)
                requestedHandle = handle
                did = try await resolve(handle: handle)
            }

            let document = try await resolveDocument(for: did)
            if let requestedHandle {
                _ = try document.verified(expecting: requestedHandle, did: did)
            }

            let pdsURL = try AtprotoAuthService.normalizePDSURL(document.pdsUrl.absoluteString)
            return AtprotoResolvedIdentity(
                handle: document.unverifiedHandle?.rawValue ?? requestedHandle?.rawValue,
                did: did.rawValue,
                pdsURL: pdsURL
            )
        } catch let error as AtprotoAuthError {
            throw error
        } catch {
            throw AtprotoAuthError.identityResolutionFailed
        }
    }

    func resolve(handle: Handle) async throws -> DID {
        let url = try makeHandleURL(handle)
        let (data, response) = try await urlSession.data(from: url)
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode,
              let rawDID = String(data: data, encoding: .utf8)?
                .split(whereSeparator: { $0.isNewline })
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AtprotoAuthError.identityResolutionFailed
        }

        return try DID(string: rawDID)
    }

    func resolveDocument(for did: DID) async throws -> DIDDocument {
        let (data, response) = try await urlSession.data(from: try makeDIDURL(did))
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode else {
            throw AtprotoAuthError.identityResolutionFailed
        }
        return try JSONDecoder().decode(DIDDocument.self, from: data)
    }

    private func makeHandleURL(_ handle: Handle) throws -> URL {
        guard let host = URL(string: "https://\(handle.rawValue)"),
              let url = URL(string: "/.well-known/atproto-did", relativeTo: host) else {
            throw AtprotoAuthError.identityResolutionFailed
        }
        return url
    }

    private func makeDIDURL(_ did: DID) throws -> URL {
        switch did.knownMethod {
        case .plc:
            guard let url = URL(string: "https://plc.directory/\(did.rawValue)") else {
                throw AtprotoAuthError.identityResolutionFailed
            }
            return url
        case .web:
            let components = did.rawValue.dropFirst("did:web:".count).split(separator: ":")
            guard let host = components.first,
                  !host.isEmpty else {
                throw AtprotoAuthError.identityResolutionFailed
            }
            let path = components.dropFirst().map(String.init)
            let pathComponent = path.isEmpty
                ? "/.well-known/did.json"
                : "/" + path.joined(separator: "/") + "/did.json"
            guard let url = URL(string: "https://\(host)\(pathComponent)") else {
                throw AtprotoAuthError.identityResolutionFailed
            }
            return url
        default:
            throw AtprotoAuthError.identityResolutionFailed
        }
    }
}

private struct AtprotoSession: Codable, Equatable, Sendable {
    let accessJwt: String
    let refreshJwt: String
    let handle: String
    let did: String
    let pdsURL: String
    let serviceEndpoint: URL
}

private struct AtprotoCreateSessionBody: Codable, Sendable {
    let identifier: String
    let password: String
}

private struct AtprotoSessionResponse: Codable, Sendable {
    let accessJwt: String
    let refreshJwt: String
    let handle: String
    let did: String
    let didDoc: DIDDocument?
}

private struct AtprotoRefreshSessionResponse: Codable, Sendable {
    let accessJwt: String
    let refreshJwt: String
    let handle: String
    let did: String
    let didDoc: DIDDocument?
}

private struct AtprotoSessionClient: Sendable {
    let urlSession: URLSession

    func createSession(identifier: String, password: String, pdsURL: String) async throws -> AtprotoSessionResponse {
        try await send(
            path: "com.atproto.server.createSession",
            pdsURL: pdsURL,
            method: "POST",
            body: AtprotoCreateSessionBody(identifier: identifier, password: password),
            response: AtprotoSessionResponse.self
        )
    }

    func refreshSession(_ session: AtprotoSession) async throws -> AtprotoRefreshSessionResponse {
        try await send(
            path: "com.atproto.server.refreshSession",
            pdsURL: session.pdsURL,
            method: "POST",
            authorization: session.refreshJwt,
            response: AtprotoRefreshSessionResponse.self
        )
    }

    func deleteSession(_ session: AtprotoSession) async throws {
        _ = try await send(
            path: "com.atproto.server.deleteSession",
            pdsURL: session.pdsURL,
            method: "POST",
            authorization: session.accessJwt,
            response: EmptyResponse.self
        )
    }

    private func send<Response: Decodable>(
        path: String,
        pdsURL: String,
        method: String,
        authorization: String? = nil,
        body: (any Encodable)? = nil,
        response: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: "\(pdsURL)/xrpc/\(path)") else {
            throw AtprotoAuthError.invalidPDSURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AtprotoAuthError.requestFailed
        }
        guard 200..<300 ~= response.statusCode else {
            throw response.statusCode == 401
                ? AtprotoAuthError.invalidAppPassword
                : AtprotoAuthError.requestFailed
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct EmptyResponse: Decodable, Sendable {}

actor AtprotoAuthService {
    private static let accountCredentialID = "atproto.account"
    private static let sessionCredentialID = "atproto.session"
    private static let passwordCredentialID = "atproto.password"

    private let metadataStore: any CredentialStore
    private let credentialStore: any CredentialStore
    private let identityResolver: any AtprotoIdentityResolving
    private let sessionClient: AtprotoSessionClient
    private let oauthService: AtprotoOAuthService

    init(
        metadataStore: any CredentialStore = KeychainCredentialStore(service: "com.ginny.atproto.metadata"),
        credentialStore: any CredentialStore = KeychainCredentialStore(service: "com.ginny.atproto.session"),
        identityResolver: any AtprotoIdentityResolving = GinnyAtprotoIdentityResolver(),
        oauthService: AtprotoOAuthService = AtprotoOAuthService()
    ) {
        self.metadataStore = metadataStore
        self.credentialStore = credentialStore
        self.identityResolver = identityResolver
        self.sessionClient = AtprotoSessionClient(urlSession: .shared)
        self.oauthService = oauthService
    }

    func restore() async -> AtprotoAuthState {
        if let account = await oauthService.restore() {
            return .signedIn(account)
        }

        guard let storedSession = storedSession() else {
            return .signedOut
        }

        do {
            let refreshed = try await sessionClient.refreshSession(storedSession)
            let session = try makeSession(from: refreshed, fallbackPDSURL: storedSession.pdsURL)
            try save(session)
            let account = makeAccount(from: session)
            try save(account)
            return .signedIn(account)
        } catch {
            guard let password = try? credentialStore.credential(for: Self.passwordCredentialID),
                  let account = storedAccount() else {
                return .signedOut
            }

            do {
                let response = try await sessionClient.createSession(
                    identifier: account.handle,
                    password: password,
                    pdsURL: account.pdsURL
                )
                let session = try makeSession(from: response, fallbackPDSURL: account.pdsURL)
                try save(session)
                return .signedIn(makeAccount(from: session))
            } catch {
                return .signedOut
            }
        }
    }

    func signIn(handle: String, appPassword: String, pdsURL: String) async throws -> AtprotoAccount {
        let normalizedHandle = try Self.normalizeHandle(handle)
        guard !appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AtprotoAuthError.invalidAppPassword
        }

        let identity = try await identityResolver.resolve(identifier: normalizedHandle)
        let normalizedPDSURL = try Self.selectPDSURL(override: pdsURL, resolved: identity.pdsURL)
        let response = try await sessionClient.createSession(
            identifier: normalizedHandle,
            password: appPassword,
            pdsURL: normalizedPDSURL
        )
        let session = try makeSession(from: response, fallbackPDSURL: normalizedPDSURL)
        guard session.did == identity.did else {
            throw AtprotoAuthError.identityVerificationFailed
        }

        let account = makeAccount(from: session)
        try save(session)
        try credentialStore.save(appPassword, for: Self.passwordCredentialID)
        try save(account)
        return account
    }

    func signInWithOAuth(identifier: String) async throws -> AtprotoAccount {
        let account = try await oauthService.signIn(identifier: identifier)
        try save(account)
        return account
    }

    func signOut() async {
        await oauthService.signOut()
        if let session = storedSession() {
            try? await sessionClient.deleteSession(session)
        }
        try? credentialStore.deleteCredential(for: Self.sessionCredentialID)
        try? credentialStore.deleteCredential(for: Self.passwordCredentialID)
        try? metadataStore.deleteCredential(for: Self.accountCredentialID)
    }

    static func normalizeHandle(_ value: String) throws -> String {
        let handle = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else {
            throw AtprotoAuthError.invalidHandle
        }
        return handle
    }

    static func normalizePDSURL(_ value: String) throws -> String {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw AtprotoAuthError.invalidPDSURL
        }

        return input.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func selectPDSURL(override: String, resolved: String) throws -> String {
        let override = override.trimmingCharacters(in: .whitespacesAndNewlines)
        return try normalizePDSURL(override.isEmpty ? resolved : override)
    }

    private func storedAccount() -> AtprotoAccount? {
        guard let value = try? metadataStore.credential(for: Self.accountCredentialID),
              let data = value.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AtprotoAccount.self, from: data)
    }

    private func storedSession() -> AtprotoSession? {
        guard let value = try? credentialStore.credential(for: Self.sessionCredentialID),
              let data = value.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AtprotoSession.self, from: data)
    }

    private func save(_ account: AtprotoAccount) throws {
        let data = try JSONEncoder().encode(account)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AtprotoAuthError.missingSession
        }
        try metadataStore.save(value, for: Self.accountCredentialID)
    }

    private func save(_ session: AtprotoSession) throws {
        let data = try JSONEncoder().encode(session)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AtprotoAuthError.missingSession
        }
        try credentialStore.save(value, for: Self.sessionCredentialID)
    }

    private func makeSession(
        from response: AtprotoSessionResponse,
        fallbackPDSURL: String
    ) throws -> AtprotoSession {
        try makeSession(
            accessJwt: response.accessJwt,
            refreshJwt: response.refreshJwt,
            handle: response.handle,
            did: response.did,
            didDocument: response.didDoc,
            fallbackPDSURL: fallbackPDSURL
        )
    }

    private func makeSession(
        from response: AtprotoRefreshSessionResponse,
        fallbackPDSURL: String
    ) throws -> AtprotoSession {
        try makeSession(
            accessJwt: response.accessJwt,
            refreshJwt: response.refreshJwt,
            handle: response.handle,
            did: response.did,
            didDocument: response.didDoc,
            fallbackPDSURL: fallbackPDSURL
        )
    }

    private func makeSession(
        accessJwt: String,
        refreshJwt: String,
        handle: String,
        did: String,
        didDocument: DIDDocument?,
        fallbackPDSURL: String
    ) throws -> AtprotoSession {
        let pdsURL = try Self.normalizePDSURL(
            didDocument.flatMap { try? $0.pdsUrl.absoluteString } ?? fallbackPDSURL
        )
        guard let serviceEndpoint = URL(string: pdsURL) else {
            throw AtprotoAuthError.invalidPDSURL
        }
        return AtprotoSession(
            accessJwt: accessJwt,
            refreshJwt: refreshJwt,
            handle: handle,
            did: did,
            pdsURL: pdsURL,
            serviceEndpoint: serviceEndpoint
        )
    }

    private func makeAccount(from session: AtprotoSession) -> AtprotoAccount {
        AtprotoAccount(
            handle: session.handle,
            did: session.did,
            pdsURL: session.pdsURL,
            serviceEndpoint: session.serviceEndpoint
        )
    }
}
