import Foundation

enum ArtefactKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case document
    case code
    case web
    case inlineWeb
}

enum ArtefactError: Error, Equatable, Sendable {
    case revisionNotFound(RevisionID)
}

struct ArtefactNetworkPolicy: Equatable, Sendable {
    static let metadataKey = "networkOrigins"

    let origins: [String]
    let isValid: Bool

    private init(normalizedOrigins: [String], isValid: Bool) {
        origins = Array(normalizedOrigins.prefix(8))
        self.isValid = isValid && normalizedOrigins.count <= 8
    }

    init(origins: [String]) {
        var normalized: [String] = []
        var isValid = true

        for origin in origins {
            guard let value = Self.normalizedOrigin(origin) else {
                isValid = false
                continue
            }
            if !normalized.contains(value) {
                normalized.append(value)
            }
        }

        self.init(normalizedOrigins: normalized, isValid: isValid)
    }

    init(metadata: [String: String]) {
        guard let encodedOrigins = metadata[Self.metadataKey] else {
            self.init(origins: [])
            return
        }

        guard let data = encodedOrigins.data(using: .utf8),
              let origins = try? JSONDecoder().decode([String].self, from: data)
        else {
            self.init(normalizedOrigins: [], isValid: false)
            return
        }

        self.init(origins: origins)
    }

    var cspConnectSource: String {
        origins.isEmpty ? "'none'" : origins.joined(separator: " ")
    }

    static func metadataValue(for origins: [String]) -> String? {
        let policy = ArtefactNetworkPolicy(origins: origins)
        guard policy.isValid, !policy.origins.isEmpty,
              let data = try? JSONEncoder().encode(policy.origins)
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func requestsNetwork(in source: String) -> Bool {
        let compact = source
            .lowercased()
            .filter { !$0.isWhitespace }
        return compact.contains("fetch(")
            || compact.contains("xmlhttprequest")
            || compact.contains("websocket")
            || compact.contains("eventsource")
            || compact.contains("sendbeacon")
            || compact.contains("src=\"http://")
            || compact.contains("src=\"https://")
            || compact.contains("src='http://")
            || compact.contains("src='https://")
            || compact.contains("href=\"http://")
            || compact.contains("href=\"https://")
            || compact.contains("href='http://")
            || compact.contains("href='https://")
            || compact.contains("url(http://")
            || compact.contains("url(https://")
    }

    private static func normalizedOrigin(_ value: String) -> String? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil,
              components.port == nil || components.port == 443,
              !Self.isBlockedHost(host)
        else {
            return nil
        }

        let port = components.port.map { ":\($0)" } ?? ""
        return "https://\(host)\(port)"
    }

    private static func isBlockedHost(_ host: String) -> Bool {
        if host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal")
            || host.hasSuffix(".home.arpa")
            || host.contains(":")
        {
            return true
        }

        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = components.compactMap { Int($0) }
        guard components.count == 4,
              octets.count == 4,
              octets.allSatisfy({ (0...255).contains($0) })
        else {
            return false
        }

        let first = octets[0]
        let second = octets[1]
        return first == 0
            || first == 10
            || first == 127
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || first >= 224
    }
}

struct ArtefactRevision: Codable, Equatable, Identifiable, Sendable {
    let id: RevisionID
    let parentID: RevisionID?
    let createdAt: Date
    let source: String
    let renderedContent: String?
    let metadata: [String: String]
}

struct ArtefactReference: Equatable, Identifiable, Sendable {
    let id: ContentBlockID
    let artefactID: ArtefactID
    let revisionID: RevisionID
    let presentation: ArtefactReferencePresentation

    init?(block: ContentBlock) {
        guard block.kind == .artefactReference,
              let artefactValue = block.attributes["artefactID"],
              let artefactUUID = UUID(uuidString: artefactValue),
              let revisionValue = block.attributes["revisionID"],
              let revisionUUID = UUID(uuidString: revisionValue),
              let presentationValue = block.attributes["presentation"],
              let presentation = ArtefactReferencePresentation(rawValue: presentationValue)
        else {
            return nil
        }

        id = block.id
        artefactID = ArtefactID(rawValue: artefactUUID)
        revisionID = RevisionID(rawValue: revisionUUID)
        self.presentation = presentation
    }
}

struct Artefact: Codable, Equatable, Identifiable, Sendable {
    let id: ArtefactID
    let createdAt: Date
    let kind: ArtefactKind
    private(set) var title: String
    private(set) var metadata: [String: String]
    private(set) var revisions: [ArtefactRevision]
    private(set) var currentRevisionID: RevisionID?

    init(
        id: ArtefactID = ArtefactID(),
        title: String,
        kind: ArtefactKind,
        createdAt: Date = Date(),
        metadata: [String: String] = [:],
        revisions: [ArtefactRevision] = [],
        currentRevisionID: RevisionID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.kind = kind
        self.metadata = metadata
        self.revisions = revisions
        self.currentRevisionID = currentRevisionID
    }

    var currentRevision: ArtefactRevision? {
        guard let currentRevisionID else { return nil }
        return revision(id: currentRevisionID)
    }

    func revision(id: RevisionID) -> ArtefactRevision? {
        revisions.first { $0.id == id }
    }

    mutating func setTitle(_ title: String) {
        self.title = title
    }

    @discardableResult
    mutating func checkpoint(
        source: String,
        renderedContent: String? = nil,
        metadata: [String: String] = [:],
        id: RevisionID = RevisionID(),
        createdAt: Date = Date()
    ) -> RevisionID {
        let revision = ArtefactRevision(
            id: id,
            parentID: currentRevisionID,
            createdAt: createdAt,
            source: source,
            renderedContent: renderedContent,
            metadata: metadata
        )
        revisions.append(revision)
        currentRevisionID = id
        return id
    }

    @discardableResult
    mutating func restore(
        revisionID: RevisionID,
        createdAt: Date = Date()
    ) throws -> RevisionID {
        guard let revision = revision(id: revisionID) else {
            throw ArtefactError.revisionNotFound(revisionID)
        }

        return checkpoint(
            source: revision.source,
            renderedContent: revision.renderedContent,
            metadata: revision.metadata,
            createdAt: createdAt
        )
    }
}
