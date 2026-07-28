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
