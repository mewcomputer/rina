import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
struct SourceImporter {
    static let defaultMaximumBytes = 10 * 1024 * 1024
    static let directTextExtractorVersion = "foundation-direct-text-v1"
    static let supportedContentTypes: [UTType] = [
        .plainText,
        .text,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        .pdf
    ]

    let attachmentStore: any AttachmentStore
    let repository: SourceRepository
    let maximumBytes: Int

    init(
        attachmentStore: any AttachmentStore,
        repository: SourceRepository,
        maximumBytes: Int = SourceImporter.defaultMaximumBytes
    ) {
        self.attachmentStore = attachmentStore
        self.repository = repository
        self.maximumBytes = maximumBytes
    }

    func importFile(at url: URL) async throws -> Source {
        let contentTypeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier
            ?? UTType.data.identifier
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
           fileSize.intValue > maximumBytes
        {
            throw SourceImportError.tooLarge(maximumBytes: maximumBytes)
        }
        return try await importData(
            Data(contentsOf: url),
            displayName: url.lastPathComponent,
            contentTypeIdentifier: contentTypeIdentifier
        )
    }

    func importData(
        _ data: Data,
        displayName: String,
        contentTypeIdentifier: String
    ) async throws -> Source {
        guard !data.isEmpty else { throw SourceImportError.emptyContent }
        guard data.count <= maximumBytes else {
            throw SourceImportError.tooLarge(maximumBytes: maximumBytes)
        }
        guard Self.isSupportedType(contentTypeIdentifier, displayName: displayName) else {
            throw SourceImportError.unsupportedContentType(contentTypeIdentifier)
        }

        let extraction = try GinnyDiagnostics.withSpan(
            OperationIdentity(name: "source.extract")
        ) {
            try Self.extract(
                data: data,
                contentTypeIdentifier: contentTypeIdentifier,
                displayName: displayName
            )
        }
        let attachment = try await attachmentStore.put(data)
        let source = Source(
            displayName: Self.safeDisplayName(displayName),
            contentTypeIdentifier: Self.canonicalTextType(
                contentTypeIdentifier,
                displayName: displayName
            ),
            byteCount: data.count,
            digest: attachment.digest,
            storageKey: attachment.storageKey,
            extractionState: extraction.state,
            extractedText: extraction.text,
            extractorVersion: extraction.version,
            extractionProvenance: extraction.provenance
        )

        do {
            try repository.upsert(source)
        } catch {
            throw SourceImportError.persistenceFailure
        }
        return source
    }

    private static func isSupportedType(
        _ identifier: String,
        displayName: String
    ) -> Bool {
        let normalized = identifier.lowercased()
        if normalized == "public.plain-text"
            || normalized == "public.text"
            || normalized == "net.daringfireball.markdown"
            || normalized == "com.adobe.pdf"
        {
            return true
        }

        let extensionValue = URL(fileURLWithPath: displayName).pathExtension.lowercased()
        return extensionValue == "txt"
            || extensionValue == "md"
            || extensionValue == "markdown"
            || extensionValue == "pdf"
    }

    private static func extract(
        data: Data,
        contentTypeIdentifier: String,
        displayName: String
    ) throws -> ExtractionResult {
        let normalized = contentTypeIdentifier.lowercased()
        let extensionValue = URL(fileURLWithPath: displayName).pathExtension.lowercased()
        if normalized == "com.adobe.pdf" || extensionValue == "pdf" {
            guard let document = PDFDocument(data: data) else {
                throw SourceImportError.extractionFailed("PDFKit could not open the document.")
            }
            let pageText = (0..<document.pageCount).compactMap { index in
                document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let text = pageText.filter { !$0.isEmpty }.joined(separator: "\n\n")
            return ExtractionResult(
                state: text.isEmpty ? .partiallyReady : .ready,
                text: text.isEmpty ? nil : text,
                version: "pdfkit-text-v1",
                provenance: "PDFKit page text extraction"
            )
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw SourceImportError.invalidTextEncoding
        }
        return ExtractionResult(
            state: .ready,
            text: text,
            version: Self.directTextExtractorVersion,
            provenance: "direct UTF-8 decoding"
        )
    }

    private static func canonicalTextType(
        _ identifier: String,
        displayName: String
    ) -> String {
        let extensionValue = URL(fileURLWithPath: displayName).pathExtension.lowercased()
        if identifier.lowercased() == "com.adobe.pdf" || extensionValue == "pdf" {
            return "com.adobe.pdf"
        }
        if identifier.lowercased() == "net.daringfireball.markdown"
            || extensionValue == "md"
            || extensionValue == "markdown"
        {
            return "net.daringfireball.markdown"
        }
        return "public.plain-text"
    }

    private static func safeDisplayName(_ displayName: String) -> String {
        let name = URL(fileURLWithPath: displayName).lastPathComponent
        return name.isEmpty ? "Imported source" : name
    }

    private struct ExtractionResult {
        let state: SourceExtractionState
        let text: String?
        let version: String
        let provenance: String
    }
}
