import XCTest
import SwiftData
@testable import Ginny

@MainActor
final class SessionHistoryTests: XCTestCase {
    func testSavingConversationAddsNewestConversationAndDerivesTitle() {
        let suiteName = "SessionHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let history = SessionHistoryStore(
            repository: try! ConversationRepository(isStoredInMemoryOnly: true),
            defaults: defaults
        )
        let conversation = Conversation(
            createdAt: Date(timeIntervalSince1970: 100),
            messages: [Message.user("Plan a quiet weekend"), Message.assistant("Start with one small ritual.")],
            generationState: .completed
        )

        history.save(conversation)

        XCTAssertEqual(history.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(history.title(for: conversation), "Plan a quiet weekend")
        XCTAssertEqual(history.preview(for: conversation), "Start with one small ritual.")
    }

    func testSavingSameConversationUpdatesItInsteadOfDuplicatingIt() {
        let suiteName = "SessionHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let history = SessionHistoryStore(
            repository: try! ConversationRepository(isStoredInMemoryOnly: true),
            defaults: defaults
        )
        let id = ConversationID()
        let first = Conversation(
            id: id,
            messages: [Message.user("First title")],
            generationState: .completed
        )
        let updated = Conversation(
            id: id,
            messages: [Message.user("Updated title"), Message.assistant("Updated answer")],
            generationState: .completed
        )

        history.save(first)
        history.save(updated)

        XCTAssertEqual(history.conversations.count, 1)
        XCTAssertEqual(history.title(for: history.conversations[0]), "Updated title")
    }

    func testGeneratingTitleUsesTheFirstMessageAndAnswerAndPersistsIt() async {
        let suiteName = "SessionHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let generator = TestConversationTitleGenerator(title: "Weekend Reset")
        let repository = try! ConversationRepository(isStoredInMemoryOnly: true)
        let history = SessionHistoryStore(
            repository: repository,
            defaults: defaults,
            titleGenerator: generator
        )
        let conversation = Conversation(
            messages: [
                Message.user("Help me plan a quiet weekend"),
                Message.assistant("Start with one small ritual and leave room for rest.")
            ],
            generationState: .completed
        )

        history.save(conversation)
        await history.generateTitle(for: conversation)

        XCTAssertEqual(history.title(for: history.conversations[0]), "Weekend Reset")
        XCTAssertEqual(generator.prompt, "Help me plan a quiet weekend")
        XCTAssertEqual(
            generator.answer,
            "Start with one small ritual and leave room for rest."
        )

        let restored = SessionHistoryStore(
            repository: repository,
            defaults: defaults,
            titleGenerator: generator
        )
        XCTAssertEqual(restored.title(for: restored.conversations[0]), "Weekend Reset")
    }

    func testTitleFormatterAimsForFourWordsWithSixOrEightWordCap() {
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("One two three four five six seven eight nine"),
            "One two three four five six seven eight"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize(
                "Conversation Endpoint Configuration Details Planning Review Archive"
            ),
            "Conversation Endpoint Configuration Details Planning Review"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("Title: \"One two\""),
            "One two"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("### \"One two\""),
            "One two"
        )
        XCTAssertEqual(
            ConversationTitleFormatter.sanitize("- One two"),
            "One two"
        )
    }

    func testConversationRepositoryRoundTripsConversationData() throws {
        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        var conversation = Conversation(
            createdAt: Date(timeIntervalSince1970: 100),
            title: "A saved session",
            messages: [
                Message.user("Hello"),
                Message(
                    role: .assistant,
                    blocks: [
                        .text("Partial answer", isComplete: false),
                        .toolCall(
                            callID: "call-1",
                            name: "current_time",
                            arguments: "{}"
                        )
                    ],
                    providerContinuations: [
                        ProviderContinuation(
                            provider: .umans,
                            id: "thinking-1",
                            kind: "reasoning",
                            fields: ["thinking": "plan"]
                        )
                    ]
                )
            ],
            generationState: .streaming
        )

        try repository.upsert(conversation)

        let restored = try XCTUnwrap(try repository.fetch().first)
        XCTAssertEqual(restored, conversation)

        conversation.setTitle("Renamed session")
        try repository.upsert(conversation)

        XCTAssertEqual(try repository.fetch().first?.title, "Renamed session")
        XCTAssertEqual(try repository.fetch().count, 1)
    }

    func testConversationRepositoryImportsLegacyUserDefaultsFixture() throws {
        let suiteName = "SessionHistoryTests.LegacyMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyConversation = Conversation(
            messages: [Message.user("Legacy prompt"), Message.assistant("Legacy answer")],
            generationState: .completed
        )
        defaults.set(
            try JSONEncoder().encode([legacyConversation]),
            forKey: "session.history"
        )

        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        let importedCount = try repository.importLegacy(from: defaults)

        XCTAssertEqual(importedCount, 1)
        XCTAssertNil(defaults.data(forKey: "session.history"))
        XCTAssertEqual(try repository.fetch(), [legacyConversation])
    }

    func testConversationRepositoryMigratesLegacyStructuredBlocksWithoutAttributes() throws {
        let suiteName = "SessionHistoryTests.LegacyStructuredBlock-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyConversation = Conversation(
            messages: [Message(
                role: .assistant,
                blocks: [.citationGroup("[]")]
            )],
            generationState: .completed
        )
        var fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode([legacyConversation])
            ) as? [[String: Any]]
        )
        var messages = try XCTUnwrap(fixture[0]["messages"] as? [[String: Any]])
        var blocks = try XCTUnwrap(messages[0]["blocks"] as? [[String: Any]])
        blocks[0].removeValue(forKey: "attributes")
        messages[0]["blocks"] = blocks
        fixture[0]["messages"] = messages
        defaults.set(
            try JSONSerialization.data(withJSONObject: fixture),
            forKey: "session.history"
        )

        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        XCTAssertEqual(try repository.importLegacy(from: defaults), 1)

        let restored = try XCTUnwrap(try repository.fetch().first)
        XCTAssertEqual(restored.messages[0].blocks[0].kind, .citationGroup)
        XCTAssertEqual(restored.messages[0].blocks[0].attributes, [:])
    }

    func testSessionHistoryRecoversInterruptedGeneration() throws {
        let repository = try ConversationRepository(isStoredInMemoryOnly: true)
        let conversation = Conversation(
            messages: [
                Message.user("Continue this"),
                Message.assistant("Partial answer", createdAt: Date(timeIntervalSince1970: 2))
            ],
            generationState: .streaming
        )
        try repository.upsert(conversation)

        let history = SessionHistoryStore(repository: repository)

        XCTAssertEqual(history.conversations.first?.generationState, .cancelled)
        XCTAssertEqual(
            history.conversations.first?.messages.last?.blocks.first?.payload,
            "Partial answer"
        )
    }

    func testLocalDataResetterClearsWorkspaceRecordsAttachmentsAndSearch() async throws {
        let container = try GinnyPersistence.makeContainer(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 100)
        let conversationID = TID().rawValue
        let messageID = TID().rawValue
        let artefactID = TID().rawValue
        let sourceID = TID().rawValue
        let relationshipID = TID().rawValue
        let citationID = TID().rawValue
        let contextID = TID().rawValue

        let message = MessageRecord(
            idValue: messageID,
            roleRaw: MessageRole.user.rawValue,
            createdAt: now,
            sortIndex: 0,
            blocksData: try JSONEncoder().encode([ContentBlock.text("hello")]),
            continuationsData: try JSONEncoder().encode([ProviderContinuation]())
        )
        let conversation = ConversationRecord(
            idValue: conversationID,
            createdAt: now,
            title: "Saved session",
            generationStateRaw: GenerationState.completed.rawValue,
            updatedAt: now,
            messageRecords: [message]
        )
        message.conversation = conversation
        context.insert(conversation)

        context.insert(ArtefactRecord(
            idValue: artefactID,
            createdAt: now,
            kindRaw: ArtefactKind.document.rawValue,
            title: "Saved artefact",
            metadataData: try JSONEncoder().encode([String: String]()),
            currentRevisionValue: nil
        ))
        context.insert(SourceRecord(
            idValue: sourceID,
            createdAt: now,
            displayName: "Imported file",
            contentTypeIdentifier: "public.plain-text",
            byteCount: 5,
            digest: String(repeating: "a", count: 64),
            storageKey: "attachment",
            extractionStateData: try JSONEncoder().encode(SourceExtractionState.ready),
            extractedText: "hello",
            extractorVersion: "test",
            extractionProvenance: "test",
            metadataData: try JSONEncoder().encode([String: String]())
        ))
        context.insert(RelationshipRecord(
            idValue: relationshipID,
            createdAt: now,
            sourceData: try JSONEncoder().encode(GraphNodeID.artefact(ArtefactID(rawValue: try TID(string: artefactID)))),
            predicateRaw: RelationshipPredicate.references.rawValue,
            targetData: try JSONEncoder().encode(GraphNodeID.source(SourceID(rawValue: try TID(string: sourceID)))),
            attributesData: try JSONEncoder().encode([String: String]())
        ))
        context.insert(CitationRecord(
            idValue: citationID,
            createdAt: now,
            query: "test",
            providerRaw: WebSearchProviderID.tavily.rawValue,
            title: "Result",
            url: "https://example.com",
            snippet: "A result",
            publishedAt: nil,
            author: nil,
            score: nil
        ))
        context.insert(ContextRecord(
            idValue: contextID,
            createdAt: now,
            name: "Saved context",
            membersData: try JSONEncoder().encode([ContextMember]())
        ))
        try context.save()

        let attachmentRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("GinnyResetTests-\(UUID().uuidString)")
        let attachmentStore = try FileAttachmentStore(rootURL: attachmentRoot)
        let attachment = try await attachmentStore.put(Data("hello".utf8))
        let searchIndex = LocalSearchIndex()
        await searchIndex.enqueue(.upsert(SearchDocument(
            id: .conversation(ConversationID(rawValue: try TID(string: conversationID))),
            kind: .conversation,
            content: "hello",
            createdAt: now
        )))
        await searchIndex.flush()

        let resetter = LocalDataResetter(
            container: container,
            attachmentStore: attachmentStore,
            searchIndex: searchIndex
        )
        try await resetter.reset()

        let verify = ModelContext(container)
        XCTAssertTrue(try verify.fetch(FetchDescriptor<ConversationRecord>()).isEmpty)
        XCTAssertTrue(try verify.fetch(FetchDescriptor<ArtefactRecord>()).isEmpty)
        XCTAssertTrue(try verify.fetch(FetchDescriptor<SourceRecord>()).isEmpty)
        XCTAssertTrue(try verify.fetch(FetchDescriptor<RelationshipRecord>()).isEmpty)
        XCTAssertTrue(try verify.fetch(FetchDescriptor<CitationRecord>()).isEmpty)
        XCTAssertTrue(try verify.fetch(FetchDescriptor<ContextRecord>()).isEmpty)
        let searchResults = await searchIndex.search(query: "hello")
        XCTAssertTrue(searchResults.isEmpty)

        do {
            _ = try await attachmentStore.load(attachment)
            XCTFail("Expected local attachments to be removed")
        } catch AttachmentStoreError.missingContent {
            // expected
        }
    }
}

private final class TestConversationTitleGenerator: ConversationTitleGenerating, @unchecked Sendable {
    let title: String?
    var prompt = ""
    var answer = ""

    init(title: String?) {
        self.title = title
    }

    func generateTitle(for prompt: String, answer: String) async -> String? {
        self.prompt = prompt
        self.answer = answer
        return title
    }
}
