import Foundation
import UIKit
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

    func testSourceImportRejectsFilesOverTheConfiguredLimit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GinnyImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try FileAttachmentStore(rootURL: root)
        let repository = try SourceRepository(isStoredInMemoryOnly: true)
        let importer = SourceImporter(
            attachmentStore: store,
            repository: repository,
            maximumBytes: 10
        )
        let fileURL = root.appendingPathComponent("large.txt")
        try Data(repeating: 0x61, count: 11).write(to: fileURL)

        do {
            _ = try await importer.importFile(at: fileURL)
            XCTFail("Expected the importer to reject an oversized file")
        } catch let error as SourceImportError {
            XCTAssertEqual(error, .tooLarge(maximumBytes: 10))
        }
    }

    func testSourceImportExtractsPDFTextAndPreservesTheOriginalType() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GinnyPDFImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try FileAttachmentStore(rootURL: root)
        let repository = try SourceRepository(isStoredInMemoryOnly: true)
        let importer = SourceImporter(attachmentStore: store, repository: repository)
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let data = renderer.pdfData { context in
            context.beginPage()
            ("Ginny PDF fixture" as NSString).draw(
                at: CGPoint(x: 24, y: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18)
                ]
            )
        }

        let source = try await importer.importData(
            data,
            displayName: "notes.pdf",
            contentTypeIdentifier: "com.adobe.pdf"
        )

        XCTAssertEqual(source.contentTypeIdentifier, "com.adobe.pdf")
        XCTAssertEqual(source.extractionState, .ready)
        XCTAssertTrue(source.extractedText?.contains("Ginny PDF fixture") == true)
        XCTAssertEqual(source.extractorVersion, "pdfkit-text-v1")
    }
}
