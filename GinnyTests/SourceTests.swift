import CryptoKit
import Foundation
import XCTest
@testable import Ginny

@MainActor
final class SourceTests: XCTestCase {
    func testFileAttachmentStoreUsesContentAddressedStorage() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileAttachmentStore(rootURL: root)
        let data = Data("hello sources".utf8)

        let attachment = try await store.put(data)
        let expectedDigest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertEqual(attachment.digest, expectedDigest)
        let loaded = try await store.load(attachment)
        XCTAssertEqual(loaded, data)
    }

    func testTextImporterCreatesReadySourceAndKeepsOriginalContentAddressed() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let attachmentStore = try FileAttachmentStore(rootURL: root)
        let repository = try SourceRepository(isStoredInMemoryOnly: true)
        let importer = SourceImporter(
            attachmentStore: attachmentStore,
            repository: repository
        )
        let data = Data("# A source\n\nKeep this exact text.".utf8)

        let source = try await importer.importData(
            data,
            displayName: "notes.md",
            contentTypeIdentifier: "net.daringfireball.markdown"
        )

        XCTAssertEqual(source.displayName, "notes.md")
        XCTAssertEqual(source.contentTypeIdentifier, "net.daringfireball.markdown")
        XCTAssertEqual(source.extractionState, .ready)
        XCTAssertEqual(source.extractedText, String(decoding: data, as: UTF8.self))
        XCTAssertEqual(source.storageKey, source.digest)
        XCTAssertEqual(try repository.fetch(), [source])
        let loaded = try await attachmentStore.load(source.attachment)
        XCTAssertEqual(loaded, data)
    }

    func testSourceRepositoryDoesNotAllowContentMutation() throws {
        let repository = try SourceRepository(isStoredInMemoryOnly: true)
        let original = Source(
            displayName: "notes.txt",
            contentTypeIdentifier: "public.plain-text",
            byteCount: 3,
            digest: "abc",
            storageKey: "abc"
        )
        try repository.upsert(original)

        var changed = original
        changed = Source(
            id: original.id,
            createdAt: original.createdAt,
            displayName: original.displayName,
            contentTypeIdentifier: original.contentTypeIdentifier,
            byteCount: 4,
            digest: "def",
            storageKey: "def",
            extractionState: original.extractionState,
            extractedText: original.extractedText,
            extractorVersion: original.extractorVersion,
            extractionProvenance: original.extractionProvenance,
            metadata: original.metadata
        )

        XCTAssertThrowsError(try repository.upsert(changed)) { error in
            XCTAssertEqual(error as? SourceRepositoryError, .immutableContentChanged)
        }
        XCTAssertEqual(try repository.fetch(), [original])
    }

    func testImporterRejectsUnsupportedTypesAndInvalidUTF8() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let importer = SourceImporter(
            attachmentStore: try FileAttachmentStore(rootURL: root),
            repository: try SourceRepository(isStoredInMemoryOnly: true)
        )

        do {
            try await importer.importData(
                Data("image".utf8),
                displayName: "image.png",
                contentTypeIdentifier: "public.png"
            )
            XCTFail("Expected an unsupported content type error")
        } catch {
            XCTAssertEqual(error as? SourceImportError, .unsupportedContentType("public.png"))
        }

        do {
            try await importer.importData(
                Data([0xff, 0xfe]),
                displayName: "notes.txt",
                contentTypeIdentifier: "public.plain-text"
            )
            XCTFail("Expected an invalid text encoding error")
        } catch {
            XCTAssertEqual(error as? SourceImportError, .invalidTextEncoding)
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GinnySourceTests-\(UUID().uuidString)", isDirectory: true)
    }
}
