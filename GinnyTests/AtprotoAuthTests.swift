import XCTest
@testable import Ginny

final class AtprotoAuthTests: XCTestCase {
    func testNormalizesHandleAndPDSURL() throws {
        XCTAssertEqual(
            try AtprotoAuthService.normalizeHandle("  alice.example.com "),
            "alice.example.com"
        )
        XCTAssertEqual(
            try AtprotoAuthService.normalizePDSURL("https://pds.example.com/"),
            "https://pds.example.com"
        )
    }

    func testRejectsInvalidAuthInputs() {
        XCTAssertThrowsError(try AtprotoAuthService.normalizeHandle(" ")) { error in
            XCTAssertEqual(error as? AtprotoAuthError, .invalidHandle)
        }
        XCTAssertThrowsError(try AtprotoAuthService.normalizePDSURL("http://localhost:2583")) { error in
            XCTAssertEqual(error as? AtprotoAuthError, .invalidPDSURL)
        }
    }

    func testAccountRoundTripsThroughCodable() throws {
        let account = AtprotoAccount(
            handle: "alice.example.com",
            did: "did:plc:example",
            pdsURL: "https://pds.example.com",
            serviceEndpoint: URL(string: "https://pds.example.com")!
        )

        let data = try JSONEncoder().encode(account)
        XCTAssertEqual(try JSONDecoder().decode(AtprotoAccount.self, from: data), account)
    }

    func testUsesResolvedPDSUnlessAnOverrideIsProvided() throws {
        XCTAssertEqual(
            try AtprotoAuthService.selectPDSURL(
                override: "",
                resolved: "https://resolved.example.com/"
            ),
            "https://resolved.example.com"
        )
        XCTAssertEqual(
            try AtprotoAuthService.selectPDSURL(
                override: " https://custom.example.com/ ",
                resolved: "https://resolved.example.com"
            ),
            "https://custom.example.com"
        )
    }

    func testOAuthConfigurationUsesRinaClientMetadataAndCallback() {
        let configuration = GinnyAtprotoOAuthConfiguration()

        XCTAssertEqual(
            configuration.clientInfo.clientId,
            "https://rina.mew.computer/oauth-client-metadata.json"
        )
        XCTAssertEqual(
            configuration.clientInfo.redirectURI,
            URL(string: "computer.mew.rina:/oauth/callback")
        )
        XCTAssertEqual(configuration.clientInfo.scopes, ["atproto"])
    }

    func testIdentityResolverUsesAtprotoHandleResolutionService() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AtprotoIdentityURLProtocol.self]
        let resolver = GinnyAtprotoIdentityResolver(
            urlSession: URLSession(configuration: configuration)
        )
        AtprotoIdentityURLProtocol.requestedURLs = []

        let identity = try await resolver.resolve(identifier: "alice.test")

        XCTAssertEqual(identity.did, "did:plc:example")
        XCTAssertEqual(identity.handle, "alice.test")
        XCTAssertEqual(identity.pdsURL, "https://pds.example.com")
        XCTAssertEqual(AtprotoIdentityURLProtocol.requestedURLs.first?.host, "public.api.bsky.app")
    }
}

private final class AtprotoIdentityURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        Self.requestedURLs.append(url)

        let statusCode: Int
        let body: Data
        if url.host == "public.api.bsky.app" {
            statusCode = 200
            body = Data("{\"did\":\"did:plc:example\"}".utf8)
        } else if url.host == "plc.directory" {
            statusCode = 200
            body = Data(
                """
                {
                  "@context": ["https://www.w3.org/ns/did/v1"],
                  "id": "did:plc:example",
                  "alsoKnownAs": ["at://alice.test"],
                  "service": [
                    {
                      "id": "#atproto_pds",
                      "type": "AtprotoPersonalDataServer",
                      "serviceEndpoint": "https://pds.example.com"
                    }
                  ]
                }
                """.utf8
            )
        } else {
            statusCode = 404
            body = Data()
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
