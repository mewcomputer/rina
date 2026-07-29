import Foundation

enum ContextMember: Codable, Equatable, Sendable {
    case message(MessageID)
    case artefactRevision(artefactID: ArtefactID, revisionID: RevisionID)
    case source(SourceID)
}

struct Context: Codable, Equatable, Identifiable, Sendable {
    let id: ContextID
    let createdAt: Date
    private(set) var name: String
    private(set) var members: [ContextMember]

    init(
        id: ContextID = ContextID(),
        createdAt: Date = Date(),
        name: String,
        members: [ContextMember] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.members = members
    }

    mutating func setName(_ name: String) {
        self.name = name
    }

    mutating func setMembers(_ members: [ContextMember]) {
        self.members = members
    }
}

enum ContextItemProvenance: Codable, Equatable, Sendable {
    case systemInstructions
    case taskConstraint(index: Int)
    case message(MessageID)
    case artefact(ArtefactID)
    case artefactRevision(artefactID: ArtefactID, revisionID: RevisionID)
    case source(SourceID)
}

enum ContextOmissionReason: Codable, Equatable, Sendable {
    case tokenBudget
    case noCurrentArtefactRevision
    case sourceExtractionUnavailable
}

struct ContextItem: Codable, Equatable, Sendable {
    let text: String
    let provenance: ContextItemProvenance
    let estimatedTokens: Int
}

struct ContextOmission: Codable, Equatable, Sendable {
    let provenance: ContextItemProvenance
    let reason: ContextOmissionReason
}

struct ContextAssemblyResult: Codable, Equatable, Sendable {
    let items: [ContextItem]
    let omissions: [ContextOmission]
    let estimatedTokens: Int
}

struct ContextAssemblyInput: Sendable {
    let systemInstructions: String
    let messages: [Message]
    let artefacts: [Artefact]
    let sources: [Source]
    let taskConstraints: [String]

    init(
        systemInstructions: String,
        messages: [Message] = [],
        artefacts: [Artefact] = [],
        sources: [Source] = [],
        taskConstraints: [String] = []
    ) {
        self.systemInstructions = systemInstructions
        self.messages = messages
        self.artefacts = artefacts
        self.sources = sources
        self.taskConstraints = taskConstraints
    }
}

protocol ContextTokenEstimating: Sendable {
    func estimateTokens(in text: String) -> Int
}

struct CharacterContextTokenEstimator: ContextTokenEstimating {
    let charactersPerToken: Int

    init(charactersPerToken: Int = 4) {
        self.charactersPerToken = max(1, charactersPerToken)
    }

    func estimateTokens(in text: String) -> Int {
        max(1, (text.count + charactersPerToken - 1) / charactersPerToken)
    }
}

enum ContextAssemblyError: Error, Equatable, Sendable {
    case requiredContextExceedsBudget
}

struct ContextAssembler: Sendable {
    let tokenEstimator: any ContextTokenEstimating

    init(tokenEstimator: any ContextTokenEstimating = CharacterContextTokenEstimator()) {
        self.tokenEstimator = tokenEstimator
    }

    func assemble(
        _ input: ContextAssemblyInput,
        tokenBudget: Int
    ) throws -> ContextAssemblyResult {
        let budget = max(0, tokenBudget)
        let requiredCandidates = [
            ContextCandidate(
                text: input.systemInstructions,
                provenance: .systemInstructions,
                isRequired: true
            )
        ] + input.taskConstraints.enumerated().map { index, constraint in
            ContextCandidate(
                text: constraint,
                provenance: .taskConstraint(index: index),
                isRequired: true
            )
        }

        let requiredItems = requiredCandidates.map(makeItem)
        let requiredTokens = requiredItems.reduce(0) { $0 + $1.estimatedTokens }
        guard requiredTokens <= budget else {
            throw ContextAssemblyError.requiredContextExceedsBudget
        }

        var items = requiredItems
        var omissions: [ContextOmission] = []
        var remainingTokens = budget - requiredTokens

        var selectedMessages: [ContextItem] = []
        for message in input.messages.reversed() {
            let candidate = ContextCandidate(
                text: text(for: message),
                provenance: .message(message.id),
                isRequired: false
            )
            let item = makeItem(candidate)
            guard item.estimatedTokens <= remainingTokens else {
                omissions.append(ContextOmission(
                    provenance: candidate.provenance,
                    reason: .tokenBudget
                ))
                continue
            }
            selectedMessages.append(item)
            remainingTokens -= item.estimatedTokens
        }
        items.append(contentsOf: selectedMessages.reversed())

        for artefact in input.artefacts {
            guard let revision = artefact.currentRevision else {
                omissions.append(ContextOmission(
                    provenance: .artefact(artefact.id),
                    reason: .noCurrentArtefactRevision
                ))
                continue
            }
            appendOptional(
                ContextCandidate(
                    text: revision.source,
                    provenance: .artefactRevision(
                        artefactID: artefact.id,
                        revisionID: revision.id
                    ),
                    isRequired: false
                ),
                to: &items,
                remainingTokens: &remainingTokens,
                omissions: &omissions
            )
        }

        for source in input.sources {
            guard let text = source.extractedText,
                  source.extractionState == .ready || source.extractionState == .partiallyReady
            else {
                omissions.append(ContextOmission(
                    provenance: .source(source.id),
                    reason: .sourceExtractionUnavailable
                ))
                continue
            }
            appendOptional(
                ContextCandidate(
                    text: text,
                    provenance: .source(source.id),
                    isRequired: false
                ),
                to: &items,
                remainingTokens: &remainingTokens,
                omissions: &omissions
            )
        }

        return ContextAssemblyResult(
            items: items,
            omissions: omissions,
            estimatedTokens: items.reduce(0) { $0 + $1.estimatedTokens }
        )
    }

    private func appendOptional(
        _ candidate: ContextCandidate,
        to items: inout [ContextItem],
        remainingTokens: inout Int,
        omissions: inout [ContextOmission]
    ) {
        let item = makeItem(candidate)
        guard item.estimatedTokens <= remainingTokens else {
            omissions.append(ContextOmission(
                provenance: candidate.provenance,
                reason: .tokenBudget
            ))
            return
        }
        items.append(item)
        remainingTokens -= item.estimatedTokens
    }

    private func makeItem(_ candidate: ContextCandidate) -> ContextItem {
        ContextItem(
            text: candidate.text,
            provenance: candidate.provenance,
            estimatedTokens: tokenEstimator.estimateTokens(in: candidate.text)
        )
    }

    private func text(for message: Message) -> String {
        message.blocks.map { block in
            switch block.kind {
            case .text, .toolResult:
                return block.payload
            case .toolCall:
                let name = block.attributes["name"] ?? "tool"
                return "[\(name)] \(block.payload)"
            case .artefactReference:
                return "[artefact reference]"
            }
        }
        .joined(separator: "\n")
    }
}

private struct ContextCandidate: Sendable {
    let text: String
    let provenance: ContextItemProvenance
    let isRequired: Bool
}
