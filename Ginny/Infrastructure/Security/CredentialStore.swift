import Foundation
import Security

protocol CredentialStore: Sendable {
    func credential(for identifier: String) throws -> String?
    func save(_ credential: String, for identifier: String) throws
    func deleteCredential(for identifier: String) throws
}

extension CredentialStore {
    func deleteCredential(for identifier: String) throws {
        _ = identifier
    }
}

struct KeychainCredentialStore: CredentialStore {
    private let service: String

    init(service: String = "com.ginny.credentials") {
        self.service = service
    }

    func credential(for identifier: String) throws -> String? {
        var query = baseQuery(identifier: identifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ credential: String, for identifier: String) throws {
        let data = Data(credential.utf8)
        let query = baseQuery(identifier: identifier)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw KeychainError.status(insertStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    func deleteCredential(for identifier: String) throws {
        let status = SecItemDelete(baseQuery(identifier: identifier) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(identifier: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
        ]
    }
}

enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
    case invalidData
}

struct InMemoryCredentialStore: CredentialStore {
    let credentials: [String: String]

    func credential(for identifier: String) throws -> String? {
        credentials[identifier]
    }

    func save(_ credential: String, for identifier: String) throws {
        fatalError("the test credential store is read-only")
    }
}
