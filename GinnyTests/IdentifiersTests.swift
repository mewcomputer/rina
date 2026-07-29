import XCTest
@testable import Ginny

final class IdentifiersTests: XCTestCase {
    func testConversationIDPreservesRawValue() {
        let rawValue = TID()
        let identifier = ConversationID(rawValue: rawValue)

        XCTAssertEqual(identifier.rawValue, rawValue)
    }

    func testConversationIDCanBeEncodedAndDecoded() throws {
        let identifier = ConversationID()
        let data = try JSONEncoder().encode(identifier)
        let decoded = try JSONDecoder().decode(ConversationID.self, from: data)

        XCTAssertEqual(decoded, identifier)
    }

    func testTIDUsesAtprotoFormat() throws {
        let tid = TID()

        XCTAssertEqual(tid.rawValue.count, TID.length)
        XCTAssertTrue(tid.rawValue.allSatisfy(TID.alphabet.contains))
        XCTAssertEqual(try TID(string: tid.rawValue), tid)
        XCTAssertThrowsError(try TID(string: "3abcdef")) { error in
            XCTAssertEqual(error as? TIDError, .invalidFormat)
        }
    }

    func testEveryDomainIdentifierUsesATIDRawValue() {
        XCTAssertNoThrow(try TID(string: ConversationID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: MessageID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: ContentBlockID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: ArtefactID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: RevisionID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: SourceID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: CitationID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: ContextID().rawValue.rawValue))
        XCTAssertNoThrow(try TID(string: RelationshipID().rawValue.rawValue))
    }
}
