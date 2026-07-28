import XCTest
@testable import Ginny

final class ToolTests: XCTestCase {
    func testCurrentTimeToolReturnsInjectedTime() async throws {
        let tool = CurrentTimeTool(now: { Date(timeIntervalSince1970: 0) })

        let result = try await tool.execute(arguments: "{}")

        XCTAssertEqual(result, "1970-01-01T00:00:00Z")
    }

    func testCurrentTimeToolRejectsArguments() async {
        let tool = CurrentTimeTool(now: { Date(timeIntervalSince1970: 0) })

        do {
            _ = try await tool.execute(arguments: "{\"timezone\":\"UTC\"}")
            XCTFail("Expected invalid arguments")
        } catch {
            XCTAssertEqual(
                error as? ToolExecutionError,
                .invalidArguments("current_time does not accept arguments.")
            )
        }
    }

    func testToolRegistryReportsUnknownTools() async {
        let registry = ToolRegistry(tools: [])

        do {
            _ = try await registry.execute(name: "missing", arguments: "{}")
            XCTFail("Expected unknown tool")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .unknownTool("missing"))
        }
    }
}
