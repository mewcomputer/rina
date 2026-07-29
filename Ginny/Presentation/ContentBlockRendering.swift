import Foundation

enum ContentBlockRendererKind: String, Codable, CaseIterable, Equatable, Sendable {
    case markdown
    case code
    case table
    case mermaid
    case image
    case fileReference
    case citationGroup
    case toolCall
    case toolResult
    case providerNotice
    case artefactReference
    case unsupported
}

struct ContentBlockRendererRegistry: Sendable {
    func rendererKind(for blockKind: ContentBlockKind) -> ContentBlockRendererKind {
        switch blockKind {
        case .text, .markdown:
            .markdown
        case .code:
            .code
        case .table:
            .table
        case .mermaid:
            .mermaid
        case .image:
            .image
        case .fileReference:
            .fileReference
        case .citationGroup:
            .citationGroup
        case .toolCall:
            .toolCall
        case .toolResult:
            .toolResult
        case .providerNotice:
            .providerNotice
        case .artefactReference:
            .artefactReference
        case .unknown:
            .unsupported
        }
    }
}
