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
    }
}
