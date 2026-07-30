import XCTest
@testable import Ginny

final class AtprotoSharingTests: XCTestCase {
    func testRecordKeysUseAtprotoTIDFormat() throws {
        XCTAssertNoThrow(try RinaRecordKey(string: "3jv3l5k7w2abc"))
        XCTAssertThrowsError(try RinaRecordKey(string: "3abcdef"))
        XCTAssertThrowsError(try RinaRecordKey(string: "3jv3l5k7w20bc"))
    }

    func testConversationSnapshotPublishesToolActivityAndVisibleThinkingButNotPrivateState() throws {
        var conversation = Conversation(title: "Web accessibility")
        try conversation.appendMessage(.user("Can you review this page?"))
        try conversation.appendMessage(
            Message(
                role: .assistant,
                blocks: [
                    .text("The page needs a clearer focus state."),
                    .toolCall(callID: "call-1", name: "search_web", arguments: "{\"q\":\"secret\"}"),
                    .toolResult(callID: "call-1", result: "private tool output"),
                ],
                providerContinuations: [
                    ProviderContinuation(
                        provider: .umans,
                        id: "reasoning-1",
                        kind: "reasoning",
                        fields: [
                            "thinking": "visible summary",
                            "signature": "private signature"
                        ],
                        privateFields: ["signature"]
                    )
                ]
            )
        )

        let snapshot = AtprotoSnapshotBuilder.conversation(conversation)

        XCTAssertEqual(snapshot.title, "Web accessibility")
        XCTAssertEqual(snapshot.messages.count, 2)
        XCTAssertEqual(
            snapshot.messages[1].blocks.map(\.kind),
            ["text", "toolCall", "toolResult"]
        )
        XCTAssertEqual(snapshot.messages[1].blocks[1].attributes["callID"], "call-1")
        XCTAssertEqual(snapshot.messages[1].providerContinuations.count, 1)
        XCTAssertEqual(snapshot.messages[1].providerContinuations[0].kind, "reasoning")
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertTrue(object["createdAt"] is String)
        XCTAssertTrue(object["updatedAt"] is String)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("visible summary"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private signature"))
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("private tool output"))
    }

    func testConversationSnapshotCarriesOptionalGenerationMetadata() throws {
        let conversation = Conversation(title: "A shared session")
        let metadata = RinaGenerationMetadata(
            provider: "Umans",
            model: "umans-coder",
            thinkingLevel: "high"
        )

        let snapshot = AtprotoSnapshotBuilder.conversation(
            conversation,
            generation: metadata
        )

        XCTAssertEqual(snapshot.generation, metadata)
        let decoded = try JSONDecoder().decode(
            RinaConversationSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.generation, metadata)
    }

    func testArtefactRecordUsesCurrentRevision() throws {
        var artefact = Artefact(title: "Accessible card", kind: .code)
        let revisionID = artefact.checkpoint(
            source: "<button>Save</button>",
            renderedContent: "<button>Save</button>",
            metadata: ["language": "html"]
        )

        let record = try AtprotoSnapshotBuilder.artefact(artefact)

        XCTAssertEqual(record.title, "Accessible card")
        XCTAssertEqual(record.kind, .code)
        XCTAssertEqual(record.id, artefact.id.rawValue.rawValue)
        XCTAssertEqual(record.revisionID, revisionID.rawValue.rawValue)
        XCTAssertEqual(record.source, "<button>Save</button>")
        XCTAssertEqual(record.metadata["language"], "html")
    }

    func testConversationSnapshotCarriesPublishedArtefactReferences() throws {
        var conversation = Conversation(title: "A shared session")
        let artefactID = ArtefactID()
        let revisionID = RevisionID()
        try conversation.appendMessage(
            Message(
                role: .assistant,
                blocks: [
                    .text("Here is the saved preview."),
                    .artefactReference(
                        artefactID: artefactID,
                        revisionID: revisionID,
                        presentation: .inline
                    )
                ]
            )
        )

        let reference = RinaArtefactReference(
            id: artefactID.rawValue.rawValue,
            revisionID: revisionID.rawValue.rawValue,
            uri: "at://did:plc:example/computer.mew.rina.artefact/3mabc234xyzab"
        )
        let snapshot = AtprotoSnapshotBuilder.conversation(
            conversation,
            artefactReferences: [reference]
        )

        XCTAssertEqual(snapshot.artefacts, [reference])
        let decoded = try JSONDecoder().decode(
            RinaConversationSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.artefacts, [reference])
    }

    func testPublicationStateRoundTrips() throws {
        let publication = AtprotoPublication(
            collection: AtprotoRecordCollection.conversation,
            rkey: "3jv3l5k7w2abc",
            uri: "at://did:plc:example/computer.mew.rina.conversation/3jv3l5k7w2abc",
            updatedAt: Date(timeIntervalSince1970: 123),
            subjectID: "conversation-1"
        )

        let data = try JSONEncoder().encode(publication)

        XCTAssertEqual(try JSONDecoder().decode(AtprotoPublication.self, from: data), publication)
        XCTAssertEqual(
            publication.publicWebURL?.absoluteString,
            "https://rina.mew.computer/s/did:plc:example/computer.mew.rina.conversation/3jv3l5k7w2abc"
        )
    }
}
