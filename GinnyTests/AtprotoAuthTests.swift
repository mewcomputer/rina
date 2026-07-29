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
}
