import SwiftUI
import XCTest
@testable import Ginny

final class ThemeTests: XCTestCase {
    func testThemeManifestResolvesBaseThemeAndTokenAliases() throws {
        let manifest = try JSONDecoder().decode(
            ThemeManifest.self,
            from: Data(
                #"""
                {
                  "version": 1,
                  "tokens": {
                    "background": "#101014",
                    "primary": "#00ffff",
                    "text.body": "@foreground",
                    "foreground": "#f5f5f5"
                  },
                  "themes": {
                    "dark": { "mode": "dark", "tokens": {} },
                    "custom": {
                      "mode": "dark",
                      "base": "dark",
                      "tokens": { "background": "#202024", "text.body": "@primary" }
                    }
                  }
                }
                """#.utf8
            )
        )

        let theme = manifest.theme(named: "custom")

        XCTAssertEqual(theme.id, "custom")
        XCTAssertEqual(theme.hexValue(for: "background"), "#202024")
        XCTAssertEqual(theme.hexValue(for: "text.body"), "#00ffff")
        XCTAssertEqual(theme.hexValue(for: "missing"), nil)
    }

    func testUnknownThemeFallsBackToDark() throws {
        let manifest = try JSONDecoder().decode(
            ThemeManifest.self,
            from: Data(
                #"""
                {
                  "version": 1,
                  "tokens": { "background": "#101014" },
                  "themes": { "dark": { "mode": "dark", "tokens": {} } }
                }
                """#.utf8
            )
        )

        XCTAssertEqual(manifest.theme(named: "does-not-exist").id, "dark")
    }
}
