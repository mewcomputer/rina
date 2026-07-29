import Foundation

enum ArtefactExportFormat: String, CaseIterable, Equatable, Sendable {
    case markdown
    case plainText
    case html

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .html: "html"
        }
    }

    var contentTypeIdentifier: String {
        switch self {
        case .markdown: "net.daringfireball.markdown"
        case .plainText: "public.plain-text"
        case .html: "public.html"
        }
    }
}

struct ExportedFile: Equatable, Identifiable, Sendable {
    let data: Data
    let filename: String
    let contentTypeIdentifier: String

    var id: String { filename }
}

enum ArtefactExportError: Error, Equatable, Sendable {
    case noCurrentRevision
}

struct ArtefactExporter: Sendable {
    func export(_ artefact: Artefact, as format: ArtefactExportFormat) throws -> ExportedFile {
        try GinnyDiagnostics.withSpan(
            OperationIdentity(name: "artefact.export")
        ) {
            guard let revision = artefact.currentRevision else {
                throw ArtefactExportError.noCurrentRevision
            }

            let content: String
            switch format {
            case .markdown, .plainText:
                content = revision.source
            case .html:
                content = revision.renderedContent ?? revision.source
            }

            return ExportedFile(
                data: Data(content.utf8),
                filename: ExportFilename.make(
                    title: artefact.title,
                    fileExtension: format.fileExtension
                ),
                contentTypeIdentifier: format.contentTypeIdentifier
            )
        }
    }
}

struct SourceExporter: Sendable {
    let attachmentStore: any AttachmentStore

    init(attachmentStore: any AttachmentStore) {
        self.attachmentStore = attachmentStore
    }

    func export(_ source: Source) async throws -> ExportedFile {
        try await GinnyDiagnostics.withSpan(
            OperationIdentity(name: "source.export")
        ) {
            ExportedFile(
                data: try await attachmentStore.load(source.attachment),
                filename: ExportFilename.safe(source.displayName),
                contentTypeIdentifier: source.contentTypeIdentifier
            )
        }
    }
}

private enum ExportFilename {
    static func make(title: String, fileExtension: String) -> String {
        "\(safe(title)).\(fileExtension)"
    }

    static func safe(_ value: String) -> String {
        let name = value
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init) ?? ""
        let sanitized = name
            .filter {
                !$0.isNewline
                    && $0.unicodeScalars.allSatisfy {
                        !CharacterSet.controlCharacters.contains($0)
                    }
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty || sanitized == "." || sanitized == ".."
            ? "Untitled"
            : sanitized
    }
}
