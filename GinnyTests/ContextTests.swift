import Foundation
import XCTest
@testable import Ginny

final class ContextTests: XCTestCase {
    func testContextReferencesObjectsWithoutOwningTheirContent() {
        let messageID = MessageID()
        let artefactID = ArtefactID()
        let revisionID = RevisionID()
        let sourceID = SourceID()
        let context = Context(
            name: "Research",
            members: [
                .message(messageID),
                .artefactRevision(artefactID: artefactID, revisionID: revisionID),
                .source(sourceID)
            ]
        )

        XCTAssertEqual(context.members, [
            .message(messageID),
            .artefactRevision(artefactID: artefactID, revisionID: revisionID),
            .source(sourceID)
        ])
    }

    func testAssemblerPreservesSystemAndRecentConversationContinuity() throws {
        let first = Message.user(String(repeating: "a", count: 20))
        let second = Message.assistant(String(repeating: "b", count: 20))
        let third = Message.user(String(repeating: "c", count: 20))
        let input = ContextAssemblyInput(
            systemInstructions: "system",
            messages: [first, second, third],
            taskConstraints: ["constraint"]
        )

        let result = try ContextAssembler(tokenEstimator: FixedTokenEstimator(tokensPerItem: 1))
            .assemble(input, tokenBudget: 4)

        XCTAssertEqual(result.items.map(\.provenance), [
            .systemInstructions,
            .taskConstraint(index: 0),
            .message(second.id),
            .message(third.id)
        ])
        XCTAssertEqual(result.omissions.map(\.provenance), [
            .message(first.id)
        ])
    }

    func testAssemblerRecordsUnavailableAndOverBudgetMaterialDeterministically() throws {
        let artefactWithoutRevision = Artefact(title: "Draft", kind: .document)
        var artefactWithRevision = Artefact(title: "Draft with content", kind: .document)
        let revisionID = artefactWithRevision.checkpoint(source: "draft")
        let source = Source(
            displayName: "notes.txt",
            contentTypeIdentifier: "public.plain-text",
            byteCount: 4,
            digest: "abc",
            storageKey: "abc",
            extractionState: .pending
        )
        let input = ContextAssemblyInput(
            systemInstructions: "system",
            artefacts: [artefactWithoutRevision, artefactWithRevision],
            sources: [source]
        )

        let assembler = ContextAssembler(tokenEstimator: FixedTokenEstimator(tokensPerItem: 1))
        let first = try assembler.assemble(input, tokenBudget: 1)
        let second = try assembler.assemble(input, tokenBudget: 1)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.items.map(\.provenance), [.systemInstructions])
        XCTAssertEqual(first.omissions, [
            ContextOmission(
                provenance: .artefact(artefactWithoutRevision.id),
                reason: .noCurrentArtefactRevision
            ),
            ContextOmission(
                provenance: .artefactRevision(
                    artefactID: artefactWithRevision.id,
                    revisionID: revisionID
                ),
                reason: .tokenBudget
            ),
            ContextOmission(
                provenance: .source(source.id),
                reason: .sourceExtractionUnavailable
            )
        ])
    }

    func testAssemblerRejectsBudgetThatCannotFitRequiredContext() {
        let input = ContextAssemblyInput(systemInstructions: "system")

        XCTAssertThrowsError(
            try ContextAssembler(tokenEstimator: FixedTokenEstimator(tokensPerItem: 2))
                .assemble(input, tokenBudget: 1)
        ) { error in
            XCTAssertEqual(error as? ContextAssemblyError, .requiredContextExceedsBudget)
        }
    }
}

private struct FixedTokenEstimator: ContextTokenEstimating {
    let tokensPerItem: Int

    func estimateTokens(in text: String) -> Int {
        tokensPerItem
    }
}
