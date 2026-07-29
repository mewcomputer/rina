import AtprotoClient
import AtprotoOAuth
import AtprotoTypes
import AuthenticationServices
import Foundation
import GermConvenience
import OAuth4Swift
import SwiftAtproto

struct GinnyAtprotoOAuthResolver: Atproto.Resolver, Sendable {
    private let identityResolver = GinnyAtprotoIdentityResolver()

    func resolve(handle: Atproto.Handle) async throws -> Atproto.DID? {
        let did = try await identityResolver.resolve(
            identifier: handle.rawValue
        ).did
        return try Atproto.DID(string: did)
    }

    func resolve(did: Atproto.DID) async throws -> Atproto.DIDDocument? {
        let identity = try await identityResolver.resolve(identifier: did.rawValue)
        guard identity.did == did.rawValue else {
            throw AtprotoAuthError.identityVerificationFailed
        }
        let swiftDID = try SwiftAtproto.DID(string: did.rawValue)
        let document = try await identityResolver.resolveDocument(for: swiftDID)
        let data = try JSONEncoder().encode(document)
        return try JSONDecoder().decode(Atproto.DIDDocument.self, from: data)
    }
}

struct GinnyAtprotoOAuthConfiguration: Sendable {
    static let defaultClientID = "https://rina.mew.computer/oauth-client-metadata.json"
    static let defaultRedirectURI = URL(string: "computer.mew.rina:/oauth/callback")!
    static let defaultScopes = ["atproto"]

    let clientInfo: OAuth.ClientInfo

    init(
        clientID: String = GinnyAtprotoOAuthConfiguration.defaultClientID,
        redirectURI: URL = GinnyAtprotoOAuthConfiguration.defaultRedirectURI,
        scopes: [String] = GinnyAtprotoOAuthConfiguration.defaultScopes
    ) {
        self.clientInfo = OAuth.ClientInfo(
            clientId: clientID,
            scopes: scopes,
            redirectURI: redirectURI
        )
    }
}

actor AtprotoOAuthService {
    private static let archiveCredentialID = "atproto.oauth.archive"

    private let metadataStore: any CredentialStore
    private let client: AtprotoOAuthClient
    private let resolver: GinnyAtprotoOAuthResolver
    private var agent: AtprotoOAuthAgent?
    private var saveTask: Task<Void, Never>?

    init(
        metadataStore: any CredentialStore = KeychainCredentialStore(service: "com.ginny.atproto.oauth"),
        configuration: GinnyAtprotoOAuthConfiguration = .init(),
        resolver: GinnyAtprotoOAuthResolver = .init(),
        authFetcher: URLSession = .manualRedirect(),
        userAuthenticator: @escaping UserAuthenticator = ASWebAuthenticationSession.userAuthenticator()
    ) {
        self.metadataStore = metadataStore
        self.resolver = resolver
        self.client = AtprotoOAuthClient(
            clientInfo: configuration.clientInfo,
            resolver: resolver,
            authFetcher: authFetcher,
            userAuthenticator: userAuthenticator
        )
    }

    func signIn(identifier: String) async throws -> AtprotoAccount {
        let normalizedIdentifier = try AtprotoAuthService.normalizeHandle(identifier)
        let identity: AuthIdentity

        if normalizedIdentifier.lowercased().hasPrefix("did:") {
            identity = .did(
                try Atproto.DID(string: normalizedIdentifier),
                handle: nil
            )
        } else {
            identity = .handle(try Atproto.Handle(string: normalizedIdentifier))
        }

        let (sessionArchive, did) = try await client.authorize(identity: identity)
        let archive = AtprotoOAuthAgent.Archive(
            did: did.rawValue,
            session: sessionArchive
        )
        let (newAgent, saveStream) = try client.restore(archive: archive)

        try save(archive)
        install(agent: newAgent, saveStream: saveStream)
        return try await makeAccount(for: did, fallbackHandle: normalizedIdentifier)
    }

    func restore() async -> AtprotoAccount? {
        guard let archive = storedArchive() else {
            return nil
        }

        do {
            let (restoredAgent, saveStream) = try client.restore(archive: archive)
            install(agent: restoredAgent, saveStream: saveStream)
            return try await makeAccount(
                for: restoredAgent.authenticatedDID,
                fallbackHandle: nil
            )
        } catch {
            return nil
        }
    }

    func signOut() {
        saveTask?.cancel()
        saveTask = nil
        agent = nil
        try? metadataStore.deleteCredential(for: Self.archiveCredentialID)
    }

    private func install(
        agent: AtprotoOAuthAgent,
        saveStream: AsyncStream<OAuth.SessionState.TokenState?>
    ) {
        saveTask?.cancel()
        self.agent = agent
        saveTask = Task { [weak self] in
            for await tokenState in saveStream {
                guard let self else { return }
                await self.persist(tokenState: tokenState)
            }
        }
    }

    private func persist(tokenState: OAuth.SessionState.TokenState?) {
        guard var archive = storedArchive(), var session = archive.session else {
            return
        }

        guard let tokenState else {
            archive.session = nil
            try? save(archive)
            return
        }

        session.tokenState = tokenState
        archive.session = session
        try? save(archive)
    }

    private func makeAccount(
        for did: Atproto.DID,
        fallbackHandle: String?
    ) async throws -> AtprotoAccount {
        guard let document = try await resolver.resolve(did: did) else {
            throw AtprotoAuthError.identityResolutionFailed
        }

        let pdsURL = try AtprotoAuthService.normalizePDSURL(
            document.pdsUrl.absoluteString
        )
        let handle = document.alsoKnownAs?
            .compactMap(URL.init(string:))
            .first(where: { $0.scheme?.lowercased() == "at" })?
            .host
            ?? fallbackHandle
            ?? did.rawValue

        return AtprotoAccount(
            handle: handle,
            did: did.rawValue,
            pdsURL: pdsURL,
            serviceEndpoint: URL(string: pdsURL)!
        )
    }

    private func storedArchive() -> AtprotoOAuthAgent.Archive? {
        guard let value = try? metadataStore.credential(for: Self.archiveCredentialID),
              let data = value.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(AtprotoOAuthAgent.Archive.self, from: data)
    }

    private func save(_ archive: AtprotoOAuthAgent.Archive) throws {
        let data = try JSONEncoder().encode(archive)
        guard let value = String(data: data, encoding: .utf8) else {
            throw AtprotoAuthError.missingSession
        }
        try metadataStore.save(value, for: Self.archiveCredentialID)
    }
}
