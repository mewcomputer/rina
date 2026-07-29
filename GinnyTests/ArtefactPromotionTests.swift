import XCTest
@testable import Ginny

final class ArtefactPromotionTests: XCTestCase {
    func testPromotionUsesAssistantTextAsDocumentSource() throws {
        let message = Message(
            role: .assistant,
            blocks: [
                .text("A quiet weekend plan."),
                .toolCall(callID: "call-1", name: "current_time", arguments: "{}"),
                .text("Leave room for rest.")
            ]
        )

        let artefact = try ArtefactPromoter.promote(
            message: message,
            kind: .document,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(artefact.kind, .document)
        XCTAssertEqual(artefact.title, "A quiet weekend plan.")
        XCTAssertEqual(
            artefact.currentRevision?.source,
            "A quiet weekend plan.\n\nLeave room for rest."
        )
        XCTAssertNil(artefact.currentRevision?.renderedContent)
    }

    func testPromotionPreservesWebSourceAndMarksPresentation() throws {
        let artefact = try ArtefactPromoter.promote(
            message: .assistant("<button>Save</button>"),
            kind: .inlineWeb,
            title: "Save button"
        )

        XCTAssertEqual(artefact.title, "Save button")
        XCTAssertEqual(artefact.currentRevision?.source, "<button>Save</button>")
        XCTAssertEqual(artefact.metadata["presentation"], "inline")
    }

    func testPromotionRejectsMessagesWithoutPromotableContent() {
        XCTAssertThrowsError(
            try ArtefactPromoter.promote(
                message: Message(role: .assistant, blocks: [.toolCall(
                    callID: "call-1",
                    name: "current_time"
                )]),
                kind: .document
            )
        ) { error in
            XCTAssertEqual(error as? ArtefactPromotionError, .emptyContent)
        }
    }
}
