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

    func testCitationGroupCanBeAssociatedWithItsToolCall() {
        let block = ContentBlock.citationGroup("[]", callID: "search-1")

        XCTAssertEqual(block.attributes["callID"], "search-1")
    }

    func testUnknownBlockKindsRemainPreservable() throws {
        let json = """
        {
          "id": { "rawValue": "3aaaaaaaaaaaa" },
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

    func testLegacyStructuredBlockWithoutAttributesMigratesWithDefaults() throws {
        let json = """
        {
          "id": { "rawValue": "3bbbbbbbbbbbb" },
          "kind": "citationGroup",
          "payload": "[]",
          "isComplete": true
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)

        XCTAssertEqual(block.attributes, [:])
        XCTAssertEqual(block.kind, .citationGroup)
        XCTAssertEqual(block.payload, "[]")
    }

    func testRendererRegistryProvidesSafeFallbackForUnknownKinds() {
        let registry = ContentBlockRendererRegistry()

        XCTAssertEqual(registry.rendererKind(for: .code), .code)
        XCTAssertEqual(registry.rendererKind(for: .citationGroup), .citationGroup)
        XCTAssertEqual(registry.rendererKind(for: .unknown("future")), .unsupported)
    }

    func testRendererRegistryCoversEveryCanonicalBlockKind() {
        let registry = ContentBlockRendererRegistry()
        let expected: [(ContentBlockKind, ContentBlockRendererKind)] = [
            (.text, .markdown),
            (.markdown, .markdown),
            (.code, .code),
            (.table, .table),
            (.mermaid, .mermaid),
            (.image, .image),
            (.fileReference, .fileReference),
            (.citationGroup, .citationGroup),
            (.toolCall, .toolCall),
            (.toolResult, .toolResult),
            (.artefactReference, .artefactReference),
            (.providerNotice, .providerNotice)
        ]

        for (blockKind, rendererKind) in expected {
            XCTAssertEqual(registry.rendererKind(for: blockKind), rendererKind)
        }

        let snapshot = expected
            .map { "\($0.0.rawValue) -> \($0.1.rawValue)" }
            .joined(separator: "\n")
        XCTAssertEqual(snapshot, """
        text -> markdown
        markdown -> markdown
        code -> code
        table -> table
        mermaid -> mermaid
        image -> image
        fileReference -> fileReference
        citationGroup -> citationGroup
        toolCall -> toolCall
        toolResult -> toolResult
        artefactReference -> artefactReference
        providerNotice -> providerNotice
        """)
    }
}
