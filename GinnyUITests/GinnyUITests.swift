import XCTest

final class GinnyUITests: XCTestCase {
    @MainActor
    func testChatSurfaceExposesPrimaryAccessibleActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["header.sessionHistory"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Start a message"].exists)
        XCTAssertTrue(app.buttons["composer.modelPicker"].exists)
        XCTAssertTrue(app.buttons["composer.contextPicker"].exists)
        XCTAssertTrue(app.buttons["composer.send"].exists)

        app.buttons["header.sessionHistory"].tap()
        XCTAssertTrue(app.buttons["sidebar.searchWorkspace"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["sidebar.settings"].exists)

        app.buttons["sidebar.settings"].tap()
        XCTAssertTrue(app.staticTexts["Provider and models"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Artefacts and web"].exists)
        XCTAssertTrue(app.staticTexts["Web search"].exists)
        XCTAssertTrue(app.staticTexts["Appearance"].exists)

        app.staticTexts["atproto account"].tap()
        XCTAssertTrue(app.buttons["OAuth"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["App password"].exists)
        XCTAssertTrue(app.staticTexts["Sign in with atproto"].exists)
        XCTAssertTrue(app.buttons["Continue in browser"].exists)
        XCTAssertFalse(app.secureTextFields["App password"].exists)

        app.buttons["App password"].tap()
        XCTAssertTrue(app.secureTextFields["App password"].waitForExistence(timeout: 2))
    }
}
