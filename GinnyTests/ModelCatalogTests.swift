import Foundation
import XCTest
@testable import Ginny

final class ModelCatalogTests: XCTestCase {
    func testUmansCatalogUsesFixedURLAndFallsBackToCachedModels() async throws {
        let suiteName = "GinnyTests.ModelCatalog.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let catalog = URLSessionModelCatalog(session: session, cacheDefaults: defaults)
        let baseURL = try XCTUnwrap(URL(string: "https://custom.umans.example"))
        ModelCatalogURLProtocol.requestedURLs = []
        let payload = Data(
            """
            {
              "umans-coder": {
                "name": "umans-coder",
                "display_name": "Umans Coder",
                "capabilities": {
                  "supports_tools": true,
                  "reasoning": {
                    "supported": true,
                    "can_disable": false,
                    "levels": [],
                    "default_level": null
                  }
                }
              }
            }
            """.utf8
        )
        ModelCatalogURLProtocol.responseData = payload
        ModelCatalogURLProtocol.statusCode = 200

        let fetchedModels = try await catalog.models(
            for: .umans,
            baseURL: baseURL,
            credential: nil
        )

        XCTAssertEqual(fetchedModels.map(\.id), ["umans-coder"])
        XCTAssertEqual(
            ModelCatalogURLProtocol.requestedURLs,
            [ProviderID.umans.catalogURL(for: baseURL)]
        )
        XCTAssertEqual(
            ProviderID.umans.catalogURL(for: baseURL).absoluteString,
            "https://api.code.umans.ai/v1/models/info"
        )

        ModelCatalogURLProtocol.statusCode = 503
        let cachedCatalog = URLSessionModelCatalog(session: session, cacheDefaults: defaults)
        let cachedModels = try await cachedCatalog.models(
            for: .umans,
            baseURL: baseURL,
            credential: nil
        )

        XCTAssertEqual(cachedModels, fetchedModels)
        XCTAssertEqual(ModelCatalogURLProtocol.requestedURLs.count, 2)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDecodesUmansCatalogWithCapabilityMetadata() throws {
        let data = Data(
            """
            {
              "umans-coder": {
                "name": "umans-coder",
                "display_name": "Umans Coder",
                "description": "The recommended coding model.",
                "capabilities": {
                  "max_completion_tokens": 262144,
                  "recommended_max_tokens": 32768,
                  "context_window": 262144,
                  "supports_vision": true,
                  "supports_tools": true,
                  "reasoning": {
                    "supported": true,
                    "can_disable": false,
                    "levels": [],
                    "default_level": null
                  }
                }
              },
              "umans-glm-5.2": {
                "name": "umans-glm-5.2",
                "display_name": "Umans GLM 5.2",
                "capabilities": {
                  "supports_vision": "via-handoff",
                  "supports_tools": true
                }
              }
            }
            """.utf8
        )

        let catalog = try JSONDecoder().decode([String: ProviderModel].self, from: data)

        XCTAssertEqual(catalog["umans-coder"]?.displayName, "Umans Coder")
        XCTAssertEqual(catalog["umans-coder"]?.capabilities.contextWindow, 262144)
        XCTAssertEqual(catalog["umans-coder"]?.capabilities.supportsVision, "true")
        XCTAssertEqual(catalog["umans-coder"]?.capabilities.reasoning?.canDisable, false)
        XCTAssertEqual(catalog["umans-glm-5.2"]?.capabilities.supportsVision, "via-handoff")
    }

    func testDecodesCodexManifestIntoProviderModelsAndThinkingLevels() throws {
        let data = Data(
            """
            {
              "models": [
                {
                  "slug": "gpt-5-codex",
                  "display_name": "GPT-5 Codex",
                  "description": "A coding model.",
                  "context_window": 272000,
                  "default_reasoning_level": "high",
                  "supported_reasoning_levels": [
                    { "effort": "low", "description": "Fast" },
                    { "effort": "high", "description": "Deep" }
                  ],
                  "supported_in_api": true,
                  "visibility": "list"
                },
                {
                  "slug": "retired-codex",
                  "display_name": "Retired",
                  "supported_in_api": false,
                  "visibility": "hidden"
                }
              ]
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(CodexModelsManifest.self, from: data)
        let models = manifest.providerModels

        XCTAssertEqual(models.map(\.id), ["gpt-5-codex"])
        XCTAssertEqual(models[0].displayName, "GPT-5 Codex")
        XCTAssertEqual(models[0].capabilities.contextWindow, 272000)
        XCTAssertEqual(
            models[0].capabilities.reasoning,
            ModelReasoningCapabilities(
                supported: true,
                canDisable: false,
                levels: ["low", "high"],
                defaultLevel: "high"
            )
        )
    }

    func testCodexCatalogFallsBackToManifestWhenRemoteCatalogFails() async throws {
        let suiteName = "GinnyTests.ModelCatalog.Codex.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let catalog = URLSessionModelCatalog(session: session, cacheDefaults: defaults)
        let baseURL = try XCTUnwrap(URL(string: "https://chatgpt.com/backend-api/codex"))
        ModelCatalogURLProtocol.requestedURLs = []
        ModelCatalogURLProtocol.statusCode = 503

        let models = try await catalog.models(
            for: .codex,
            baseURL: baseURL,
            credential: "access-token"
        )

        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains(where: { $0.id == "gpt-5.6-sol" }))
        XCTAssertEqual(
            ModelCatalogURLProtocol.requestedURLs,
            [ProviderID.codex.catalogURL(for: baseURL)]
        )

        ModelCatalogURLProtocol.statusCode = 401
        do {
            _ = try await catalog.models(
                for: .codex,
                baseURL: baseURL,
                credential: "access-token"
            )
            XCTFail("Expected Codex authentication failure")
        } catch {
            XCTAssertEqual(
                error as? ProviderError,
                .httpStatus(401, message: nil)
            )
        }

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCodexCatalogRejectsCustomEndpointsBeforeSendingOAuthToken() async throws {
        let suiteName = "GinnyTests.ModelCatalog.Codex.Custom." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let catalog = URLSessionModelCatalog(
            session: URLSession(configuration: configuration),
            cacheDefaults: defaults
        )

        do {
            _ = try await catalog.models(
                for: .codex,
                baseURL: URL(string: "https://proxy.example/codex")!,
                credential: "access-token"
            )
            XCTFail("Expected custom Codex endpoint to be rejected")
        } catch {
            XCTAssertEqual(
                error as? ProviderError,
                .invalidConfiguration("Codex only supports the official ChatGPT endpoint.")
            )
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCodexCatalogRejectsHTTPOfficialHostBeforeSendingOAuthToken() async throws {
        let suiteName = "GinnyTests.ModelCatalog.Codex.HTTP." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let catalog = URLSessionModelCatalog(
            session: URLSession(configuration: configuration),
            cacheDefaults: defaults
        )

        do {
            _ = try await catalog.models(
                for: .codex,
                baseURL: URL(string: "http://chatgpt.com/backend-api/codex")!,
                credential: "access-token"
            )
            XCTFail("Expected HTTP Codex endpoint to be rejected")
        } catch {
            XCTAssertEqual(
                error as? ProviderError,
                .invalidConfiguration("Codex only supports the official ChatGPT endpoint.")
            )
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCodexCatalogRejectsOfficialHostWrongPathBeforeSendingOAuthToken() async throws {
        let suiteName = "GinnyTests.ModelCatalog.Codex.Path." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        let catalog = URLSessionModelCatalog(
            session: URLSession(configuration: configuration),
            cacheDefaults: defaults
        )

        do {
            _ = try await catalog.models(
                for: .codex,
                baseURL: URL(string: "https://chatgpt.com/backend-api/other")!,
                credential: "access-token"
            )
            XCTFail("Expected wrong Codex path to be rejected")
        } catch {
            XCTAssertEqual(
                error as? ProviderError,
                .invalidConfiguration("Codex only supports the official ChatGPT endpoint.")
            )
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class ModelCatalogURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestedURLs.append(request.url!)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.statusCode == 200 {
            client?.urlProtocol(self, didLoad: Self.responseData)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
