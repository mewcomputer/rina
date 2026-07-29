import XCTest
@testable import Ginny

@MainActor
final class ArtefactTests: XCTestCase {
    func testCheckpointCreatesImmutableLineageAndUpdatesCurrentRevision() throws {
        let createdAt = Date(timeIntervalSince1970: 100)
        var artefact = Artefact(
            title: "Weekend plan",
            kind: .document,
            createdAt: createdAt
        )

        let firstRevisionID = artefact.checkpoint(
            source: "Start with rest.",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let secondRevisionID = artefact.checkpoint(
            source: "Start with rest and one small ritual.",
            createdAt: Date(timeIntervalSince1970: 300)
        )

        XCTAssertEqual(artefact.currentRevision?.id, secondRevisionID)
        XCTAssertEqual(artefact.revisions.map(\.id), [firstRevisionID, secondRevisionID])
        XCTAssertEqual(artefact.revision(id: firstRevisionID)?.source, "Start with rest.")
        XCTAssertEqual(artefact.revision(id: secondRevisionID)?.parentID, firstRevisionID)
    }

    func testRestoringRevisionCreatesNewRevisionWithoutRewritingHistory() throws {
        var artefact = Artefact(title: "Notes", kind: .document)
        let firstRevisionID = artefact.checkpoint(source: "first")
        _ = artefact.checkpoint(source: "second")

        let restoredRevisionID = try artefact.restore(
            revisionID: firstRevisionID,
            createdAt: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(artefact.currentRevision?.id, restoredRevisionID)
        XCTAssertEqual(artefact.currentRevision?.source, "first")
        XCTAssertEqual(artefact.revisions.count, 3)
        XCTAssertEqual(artefact.revision(id: firstRevisionID)?.source, "first")
        XCTAssertEqual(artefact.currentRevision?.parentID, artefact.revisions[1].id)
    }

    func testArtefactKindsIncludeInlineWebAndRoundTrip() throws {
        let artefact = Artefact(
            title: "Budget widget",
            kind: .inlineWeb,
            metadata: ["framework": "react", "styling": "tailwind"]
        )

        let data = try JSONEncoder().encode(artefact)
        let decoded = try JSONDecoder().decode(Artefact.self, from: data)

        XCTAssertEqual(decoded, artefact)
        XCTAssertEqual(decoded.kind, .inlineWeb)
        XCTAssertEqual(decoded.metadata["styling"], "tailwind")
    }

    func testWebPreviewInjectsShadcnTokensAndTailwindStyleUtilities() {
        let document = WebArtefactPreview.document(
            for: "<html><head><title>Preview</title></head><body><button class=\"bg-primary text-primary-foreground rounded-lg\">Save</button></body></html>",
            isInline: true,
            cssVariables: [
                "background": "#101014",
                "foreground": "#f5f5f5",
                "primary": "#8fd3ff"
            ]
        )

        XCTAssertTrue(document.contains("--background: #101014;"))
        XCTAssertTrue(document.contains("--foreground: #f5f5f5;"))
        XCTAssertTrue(document.contains("--primary: #8fd3ff;"))
        XCTAssertTrue(document.contains(".bg-primary"))
        XCTAssertTrue(document.contains(".text-primary-foreground"))
        XCTAssertTrue(document.contains(".rounded-lg"))
        XCTAssertTrue(document.contains("<title>Preview</title>"))
    }

    func testWebPreviewWrapsFragmentsWithInjectedHead() {
        let document = WebArtefactPreview.document(
            for: "<button>Save</button>",
            isInline: true
        )

        XCTAssertTrue(document.contains("<!doctype html>"))
        XCTAssertTrue(document.contains("<head>"))
        XCTAssertTrue(document.contains("<style>"))
        XCTAssertTrue(document.contains("<body><button>Save</button></body>"))
    }
}
