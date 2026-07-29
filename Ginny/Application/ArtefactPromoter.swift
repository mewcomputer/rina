import Foundation

enum ArtefactPromotionError: Error, Equatable, Sendable {
    case emptyContent
}

enum ArtefactPromoter {
    static func promote(
        message: Message,
        kind: ArtefactKind,
        title: String? = nil,
        createdAt: Date = Date()
    ) throws -> Artefact {
        let source = message.blocks
            .filter { $0.kind == .text }
            .map(\.payload)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        guard !source.isEmpty else {
            throw ArtefactPromotionError.emptyContent
        }

        let presentation: String
        switch kind {
        case .inlineWeb:
            presentation = "inline"
        case .web:
            presentation = "full"
        case .document, .code:
            presentation = "native"
        }

        var artefact = Artefact(
            title: title ?? defaultTitle(for: source),
            kind: kind,
            createdAt: createdAt,
            metadata: ["presentation": presentation, "origin": "conversation"]
        )
        _ = artefact.checkpoint(source: source, createdAt: createdAt)
        return artefact
    }

    private static func defaultTitle(for source: String) -> String {
        let firstLine = source
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Untitled artefact"
        return firstLine.count > 48 ? String(firstLine.prefix(48)) + "…" : firstLine
    }
}
