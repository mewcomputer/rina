import Foundation
import UniformTypeIdentifiers

@MainActor
struct SourceImporter {
    static let defaultMaximumBytes = 10 * 1024 * 1024
    static let directTextExtractorVersion = "foundation-direct-text-v1"

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
        guard Self.isSupportedTextType(contentTypeIdentifier, displayName: displayName) else {
            throw SourceImportError.unsupportedContentType(contentTypeIdentifier)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SourceImportError.invalidTextEncoding
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
            extractionState: .ready,
            extractedText: text,
            extractorVersion: Self.directTextExtractorVersion,
            extractionProvenance: "direct UTF-8 decoding"
        )

        do {
            try repository.upsert(source)
        } catch {
            throw SourceImportError.persistenceFailure
        }
        return source
    }

    private static func isSupportedTextType(
        _ identifier: String,
        displayName: String
    ) -> Bool {
        let normalized = identifier.lowercased()
        if normalized == "public.plain-text"
            || normalized == "public.text"
            || normalized == "net.daringfireball.markdown"
        {
            return true
        }

        let extensionValue = URL(fileURLWithPath: displayName).pathExtension.lowercased()
        return extensionValue == "txt"
            || extensionValue == "md"
            || extensionValue == "markdown"
    }

    private static func canonicalTextType(
        _ identifier: String,
        displayName: String
    ) -> String {
        let extensionValue = URL(fileURLWithPath: displayName).pathExtension.lowercased()
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
}
