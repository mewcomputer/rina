import Foundation
import XCTest
@testable import Ginny

final class ModelCatalogTests: XCTestCase {
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
