import Foundation
import XCTest
@testable import Ginny

@MainActor
final class ProviderSettingsTests: XCTestCase {
    func testSavingSettingsPersistsNonSecretValuesAndUsesCredentialStore() throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let credentials = TestCredentialStore()
        let settings = ProviderSettings(defaults: defaults, credentialStore: credentials)

        settings.modelText = "example-model"
        settings.credentialText = "secret"

        XCTAssertTrue(settings.save())
        XCTAssertEqual(defaults.string(forKey: "provider.model"), "example-model")
        XCTAssertEqual(credentials.values[ProviderSettings.credentialID], "secret")
        XCTAssertEqual(settings.configuration?.model, "example-model")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSavingRemoteHTTPEndpointIsRejected() throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = ProviderSettings(
            defaults: defaults,
            credentialStore: TestCredentialStore()
        )
        settings.endpointText = "http://provider.example/v1/chat/completions"
        settings.modelText = "example-model"
        settings.credentialText = "secret"

        XCTAssertFalse(settings.save())
        XCTAssertEqual(
            settings.validationMessage,
            "Use HTTPS, or a localhost endpoint for local development."
        )

        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class TestCredentialStore: CredentialStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func credential(for identifier: String) throws -> String? {
        values[identifier]
    }

    func save(_ credential: String, for identifier: String) throws {
        values[identifier] = credential
    }
}
