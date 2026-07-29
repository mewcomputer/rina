import CryptoKit
import Foundation

enum AttachmentStoreError: Error, Equatable, Sendable {
    case invalidDigest
    case missingContent(String)
    case corruptContent(expected: String, actual: String)
}

protocol AttachmentStore: Sendable {
    func put(_ data: Data) async throws -> SourceAttachment
    func load(_ attachment: SourceAttachment) async throws -> Data
    func removeAll() async throws
}

extension AttachmentStore {
    func removeAll() async throws {}
}

actor FileAttachmentStore: AttachmentStore {
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    func put(_ data: Data) async throws -> SourceAttachment {
        let digest = Self.digest(for: data)
        let destination = try destinationURL(for: digest)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination)
            try validate(existing, expectedDigest: digest)
            return SourceAttachment(
                digest: digest,
                byteCount: existing.count,
                storageKey: digest
            )
        }

        let temporary = rootURL.appendingPathComponent(".staged-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        do {
            try fileManager.moveItem(at: temporary, to: destination)
        } catch CocoaError.fileWriteFileExists {
            try? fileManager.removeItem(at: temporary)
            let existing = try Data(contentsOf: destination)
            try validate(existing, expectedDigest: digest)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        return SourceAttachment(digest: digest, byteCount: data.count, storageKey: digest)
    }

    func load(_ attachment: SourceAttachment) async throws -> Data {
        let destination = try destinationURL(for: attachment.digest)
        guard fileManager.fileExists(atPath: destination.path) else {
            throw AttachmentStoreError.missingContent(attachment.digest)
        }

        let data = try Data(contentsOf: destination)
        try validate(data, expectedDigest: attachment.digest)
        guard data.count == attachment.byteCount else {
            throw AttachmentStoreError.corruptContent(
                expected: attachment.digest,
                actual: Self.digest(for: data)
            )
        }
        return data
    }

    func removeAll() async throws {
        for item in try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            try fileManager.removeItem(at: item)
        }
    }

    private func destinationURL(for digest: String) throws -> URL {
        guard digest.count == 64,
              digest.allSatisfy({ $0.isHexDigit })
        else {
            throw AttachmentStoreError.invalidDigest
        }

        return rootURL
            .appendingPathComponent(String(digest.prefix(2)), isDirectory: true)
            .appendingPathComponent(digest, isDirectory: false)
    }

    private func validate(_ data: Data, expectedDigest: String) throws {
        let actualDigest = Self.digest(for: data)
        guard actualDigest == expectedDigest else {
            throw AttachmentStoreError.corruptContent(
                expected: expectedDigest,
                actual: actualDigest
            )
        }
    }

    private static func digest(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
