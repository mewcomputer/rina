import XCTest
@testable import Ginny

final class IdentifiersTests: XCTestCase {
    func testConversationIDPreservesRawValue() {
        let rawValue = UUID()
        let identifier = ConversationID(rawValue: rawValue)

        XCTAssertEqual(identifier.rawValue, rawValue)
    }

    func testConversationIDCanBeEncodedAndDecoded() throws {
        let identifier = ConversationID()
        let data = try JSONEncoder().encode(identifier)
        let decoded = try JSONDecoder().decode(ConversationID.self, from: data)

        XCTAssertEqual(decoded, identifier)
    }
}
