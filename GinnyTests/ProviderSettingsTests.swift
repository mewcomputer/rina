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
        XCTAssertEqual(defaults.string(forKey: "provider.id"), ProviderID.umans.rawValue)
        XCTAssertEqual(defaults.string(forKey: "provider.model"), "example-model")
        XCTAssertEqual(credentials.values[ProviderSettings.credentialID], "secret")
        XCTAssertEqual(settings.configuration?.provider, .umans)
        XCTAssertEqual(
            settings.configuration?.endpoint.absoluteString,
            "https://api.code.umans.ai/v1/messages"
        )
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

    func testRefreshingUmansModelsSelectsTheDefaultModel() async throws {
        let suiteName = "GinnyTests.ProviderSettings.(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = ProviderSettings(
            defaults: defaults,
            credentialStore: TestCredentialStore(),
            modelCatalog: TestModelCatalog(models: [
                ProviderModel(id: "umans-flash", displayName: "Umans Flash"),
                ProviderModel(id: "umans-coder", displayName: "Umans Coder")
            ])
        )

        settings.modelText = "retired-model"
        await settings.refreshModels()

        XCTAssertEqual(settings.availableModels.map(\.id), ["umans-flash", "umans-coder"])
        XCTAssertEqual(settings.modelText, "umans-coder")
        XCTAssertNil(settings.catalogMessage)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testProviderSelectionKeepsIndependentServiceSettings() throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let credentials = TestCredentialStore()
        let settings = ProviderSettings(defaults: defaults, credentialStore: credentials)

        settings.modelText = "umans-coder"
        settings.credentialText = "umans-secret"
        XCTAssertTrue(settings.save())

        settings.selectProvider(.kimi)
        XCTAssertEqual(settings.endpointText, "https://api.moonshot.ai/v1")
        settings.modelText = "kimi-k2.5"
        settings.credentialText = "kimi-secret"
        XCTAssertTrue(settings.save())

        settings.selectProvider(.umans)
        XCTAssertEqual(settings.modelText, "umans-coder")
        XCTAssertEqual(settings.credentialText, "umans-secret")
        settings.selectProvider(.kimi)
        XCTAssertEqual(settings.modelText, "kimi-k2.5")
        XCTAssertEqual(settings.credentialText, "kimi-secret")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testKimiCodeUsesItsOwnCodingServiceDefaults() async throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = ProviderSettings(
            defaults: defaults,
            credentialStore: TestCredentialStore(),
            modelCatalog: URLSessionModelCatalog()
        )

        settings.selectProvider(.kimiCode)

        XCTAssertEqual(settings.endpointText, "https://api.kimi.com/coding/v1")
        XCTAssertEqual(settings.modelText, "kimi-for-coding")
        await settings.refreshModels()

        XCTAssertEqual(
            settings.availableModels.map(\.id),
            ["k3", "k3-256k", "kimi-for-coding", "kimi-for-coding-highspeed"]
        )
        XCTAssertNil(settings.catalogMessage)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testKimiCodeKeepsItsCredentialSeparateFromRegularKimi() throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let credentials = TestCredentialStore()
        let settings = ProviderSettings(defaults: defaults, credentialStore: credentials)

        settings.selectProvider(.kimiCode)
        settings.modelText = "kimi-for-coding"
        settings.credentialText = "coding-secret"
        XCTAssertTrue(settings.save())

        settings.selectProvider(.kimi)
        XCTAssertEqual(settings.credentialText, "")
        settings.modelText = "kimi-k2.5"
        settings.credentialText = "moonshot-secret"
        XCTAssertTrue(settings.save())

        settings.selectProvider(.kimiCode)
        XCTAssertEqual(settings.credentialText, "coding-secret")
        XCTAssertEqual(credentials.values["kimi-api-key"], "moonshot-secret")
        XCTAssertEqual(credentials.values["kimi-code-api-key"], "coding-secret")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testKimiCodeThinkingLevelIsModelAwareAndPersistent() throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = ProviderSettings(defaults: defaults, credentialStore: TestCredentialStore())

        settings.selectProvider(.kimiCode)
        XCTAssertEqual(settings.thinkingOptions, [.off, .on])
        settings.selectThinkingLevel(.off)
        XCTAssertEqual(settings.thinkingLevel, .off)

        settings.selectModel("k3")
        XCTAssertEqual(settings.thinkingOptions, [.off, .low, .high, .max])
        settings.selectThinkingLevel(.max)
        XCTAssertEqual(settings.thinkingLevel, .max)

        let restored = ProviderSettings(defaults: defaults, credentialStore: TestCredentialStore())
        restored.selectProvider(.kimiCode)
        XCTAssertEqual(restored.thinkingLevel, .off)
        restored.selectModel("k3")
        XCTAssertEqual(restored.thinkingLevel, .max)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testModelReasoningMetadataProvidesThinkingOptionsAndPersistsSelection() async throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = ProviderSettings(
            defaults: defaults,
            credentialStore: TestCredentialStore(),
            modelCatalog: TestModelCatalog(models: [
                ProviderModel(
                    id: "umans-reasoning",
                    displayName: "Umans Reasoning",
                    capabilities: ModelCapabilities(
                        reasoning: ModelReasoningCapabilities(
                            supported: true,
                            canDisable: true,
                            levels: ["low", "medium", "high"],
                            defaultLevel: "high"
                        )
                    )
                )
            ])
        )

        settings.selectModel("umans-reasoning")
        await settings.refreshModels()

        XCTAssertEqual(settings.thinkingOptions, [.off, .low, .medium, .high])
        XCTAssertEqual(settings.thinkingLevel, .high)
        settings.selectThinkingLevel(.medium)
        XCTAssertEqual(settings.thinkingLevel, .medium)

        settings.selectModel("umans-reasoning")
        XCTAssertEqual(settings.thinkingLevel, .medium)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testMigratesLegacyFullEndpointToProviderBaseURL() throws {
        let suiteName = "GinnyTests.ProviderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let credentials = TestCredentialStore()
        credentials.values[ProviderSettings.credentialID] = "secret"
        defaults.set("https://api.code.umans.ai/v1/messages", forKey: "provider.endpoint")

        let settings = ProviderSettings(defaults: defaults, credentialStore: credentials)

        XCTAssertEqual(settings.endpointText, "https://api.code.umans.ai")
        XCTAssertEqual(
            settings.configuration?.endpoint.absoluteString,
            "https://api.code.umans.ai/v1/messages"
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

private struct TestModelCatalog: ModelCatalogProviding {
    let models: [ProviderModel]

    func models(
        for provider: ProviderID,
        baseURL: URL,
        credential: String?
    ) async throws -> [ProviderModel] {
        return models
    }
}
