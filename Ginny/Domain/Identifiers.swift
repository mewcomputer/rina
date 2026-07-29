import Foundation

enum TIDError: Error, Equatable, Sendable {
    case invalidFormat
}

struct TID: Codable, Equatable, Hashable, RawRepresentable, Sendable, CustomStringConvertible {
    static let length = 13
    static let alphabet = "234567abcdefghijklmnopqrstuvwxyz"
    private static let firstCharacterAlphabet = "234567abcdefghij"

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init() {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let clockID = UInt64.random(in: 0...1023)
        rawValue = Self.encode((timestamp << 10) | clockID)
    }

    static func stable(from value: String) -> TID {
        let hash = value.utf8.reduce(into: UInt64(1469598103934665603)) { hash, byte in
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let timestampRange = (UInt64(1) << 60) - 1
        return TID(rawValue: Self.encode((UInt64(1) << 60) | (hash & timestampRange)))
    }

    init(string: String) throws {
        guard string.count == Self.length,
              string.first.map(Self.firstCharacterAlphabet.contains) == true,
              string.allSatisfy(Self.alphabet.contains)
        else {
            throw TIDError.invalidFormat
        }
        rawValue = string
    }

    init(from decoder: Decoder) throws {
        try self.init(string: String(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }

    var description: String { rawValue }

    private static func encode(_ value: UInt64) -> String {
        var value = value
        let characters = Array(Self.alphabet)
        var result = String(repeating: "2", count: Self.length)
        for index in stride(from: Self.length - 1, through: 0, by: -1) {
            result.replaceSubrange(
                result.index(result.startIndex, offsetBy: index)...result.index(result.startIndex, offsetBy: index),
                with: String(characters[Int(value & 31)])
            )
            value >>= 5
        }
        return result
    }
}

struct ConversationID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct MessageID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct ContentBlockID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct ArtefactID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct RevisionID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct SourceID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct CitationID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct ContextID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}

struct RelationshipID: Hashable, Codable, RawRepresentable, Sendable {
    let rawValue: TID

    init(rawValue: TID = TID()) {
        self.rawValue = rawValue
    }
}
