import Foundation
import XCTest
@testable import Ginny

@MainActor
final class ImportExportTests: XCTestCase {
    func testMarkdownAndTextExportsPreserveTheCurrentSource() throws {
        var artefact = Artefact(title: "Release plan", kind: .document)
        let source = "# Release plan\n\nShip the search slice."
        _ = artefact.checkpoint(source: source)

        let markdown = try ArtefactExporter().export(artefact, as: .markdown)
        let text = try ArtefactExporter().export(artefact, as: .plainText)

        XCTAssertEqual(markdown.data, Data(source.utf8))
        XCTAssertEqual(markdown.filename, "Release plan.md")
        XCTAssertEqual(markdown.contentTypeIdentifier, "net.daringfireball.markdown")
        XCTAssertEqual(text.data, Data(source.utf8))
        XCTAssertEqual(text.filename, "Release plan.txt")
        XCTAssertEqual(text.contentTypeIdentifier, "public.plain-text")
    }

    func testHTMLExportUsesCanonicalRenderedContentWhenAvailable() throws {
        var artefact = Artefact(title: "Preview", kind: .web)
        _ = artefact.checkpoint(
            source: "<p>source</p>",
            renderedContent: "<!doctype html><p>rendered</p>"
        )

        let export = try ArtefactExporter().export(artefact, as: .html)

        XCTAssertEqual(export.data, Data("<!doctype html><p>rendered</p>".utf8))
        XCTAssertEqual(export.filename, "Preview.html")
        XCTAssertEqual(export.contentTypeIdentifier, "public.html")
    }

    func testSourceExportReadsOriginalContentAddressedBytes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GinnyExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileAttachmentStore(rootURL: root)
        let data = Data("original source".utf8)
        let attachment = try await store.put(data)
        let source = Source(
            displayName: "notes.md",
            contentTypeIdentifier: "net.daringfireball.markdown",
            byteCount: data.count,
            digest: attachment.digest,
            storageKey: attachment.storageKey
        )

        let export = try await SourceExporter(attachmentStore: store).export(source)

        XCTAssertEqual(export.data, data)
        XCTAssertEqual(export.filename, "notes.md")
        XCTAssertEqual(export.contentTypeIdentifier, "net.daringfireball.markdown")
    }

    func testArtefactExportRequiresACurrentRevision() {
        let artefact = Artefact(title: "Empty", kind: .document)

        XCTAssertThrowsError(try ArtefactExporter().export(artefact, as: .markdown)) { error in
            XCTAssertEqual(error as? ArtefactExportError, .noCurrentRevision)
        }
    }
}
