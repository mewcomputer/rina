import Foundation

enum SourceExtractionState: Codable, Equatable, Sendable {
    case pending
    case extracting
    case ready
    case partiallyReady
    case failed(String)
}

enum SourceImportError: Error, Equatable, Sendable {
    case emptyContent
    case invalidTextEncoding
    case unsupportedContentType(String)
    case tooLarge(maximumBytes: Int)
    case persistenceFailure
}

struct SourceAttachment: Codable, Equatable, Sendable {
    let digest: String
    let byteCount: Int
    let storageKey: String
}

struct Source: Codable, Equatable, Identifiable, Sendable {
    let id: SourceID
    let createdAt: Date
    private(set) var displayName: String
    let contentTypeIdentifier: String
    let byteCount: Int
    let digest: String
    let storageKey: String
    private(set) var extractionState: SourceExtractionState
    private(set) var extractedText: String?
    private(set) var extractorVersion: String?
    private(set) var extractionProvenance: String?
    private(set) var metadata: [String: String]

    init(
        id: SourceID = SourceID(),
        createdAt: Date = Date(),
        displayName: String,
        contentTypeIdentifier: String,
        byteCount: Int,
        digest: String,
        storageKey: String,
        extractionState: SourceExtractionState = .pending,
        extractedText: String? = nil,
        extractorVersion: String? = nil,
        extractionProvenance: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.displayName = displayName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.digest = digest
        self.storageKey = storageKey
        self.extractionState = extractionState
        self.extractedText = extractedText
        self.extractorVersion = extractorVersion
        self.extractionProvenance = extractionProvenance
        self.metadata = metadata
    }

    var attachment: SourceAttachment {
        SourceAttachment(digest: digest, byteCount: byteCount, storageKey: storageKey)
    }

    mutating func setDisplayName(_ displayName: String) {
        self.displayName = displayName
    }

    func withExtraction(
        state: SourceExtractionState,
        text: String?,
        extractorVersion: String?,
        provenance: String?
    ) -> Source {
        Source(
            id: id,
            createdAt: createdAt,
            displayName: displayName,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: byteCount,
            digest: digest,
            storageKey: storageKey,
            extractionState: state,
            extractedText: text,
            extractorVersion: extractorVersion,
            extractionProvenance: provenance,
            metadata: metadata
        )
    }
}
