import XCTest
@testable import Ginny

final class ContentBlockTests: XCTestCase {
    func testStructuredBlockKindsRoundTripWithVersionedPayloadMetadata() throws {
        let blocks: [ContentBlock] = [
            .markdown("# Heading"),
            .code("print(\"hello\")", language: "swift"),
            .table("[{\"name\":\"Ginny\"}]"),
            .mermaid("graph TD; A-->B"),
            .image(reference: "https://example.com/image.png", mimeType: "image/png", alt: "Example"),
            .fileReference(sourceID: SourceID(), displayName: "notes.md"),
            .citationGroup("[{\"source\":\"notes.md\"}]"),
            .providerNotice("The provider did not return citations.")
        ]

        for block in blocks {
            let decoded = try JSONDecoder().decode(
                ContentBlock.self,
                from: JSONEncoder().encode(block)
            )
            XCTAssertEqual(decoded, block)
            XCTAssertEqual(block.attributes[ContentBlock.schemaVersionKey], "1")
        }
    }

    func testUnknownBlockKindsRemainPreservable() throws {
        let json = """
        {
          "id": { "rawValue": "00000000-0000-0000-0000-000000000001" },
          "kind": "futureBlock",
          "payload": "future payload",
          "attributes": { "schemaVersion": "4" },
          "isComplete": true
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)

        XCTAssertEqual(block.kind, .unknown("futureBlock"))
        XCTAssertEqual(block.payload, "future payload")
        XCTAssertEqual(block.attributes[ContentBlock.schemaVersionKey], "4")
        XCTAssertEqual(
            try JSONDecoder().decode(
                ContentBlock.self,
                from: JSONEncoder().encode(block)
            ),
            block
        )
    }

    func testRendererRegistryProvidesSafeFallbackForUnknownKinds() {
        let registry = ContentBlockRendererRegistry()

        XCTAssertEqual(registry.rendererKind(for: .code), .code)
        XCTAssertEqual(registry.rendererKind(for: .citationGroup), .citationGroup)
        XCTAssertEqual(registry.rendererKind(for: .unknown("future")), .unsupported)
    }
}
