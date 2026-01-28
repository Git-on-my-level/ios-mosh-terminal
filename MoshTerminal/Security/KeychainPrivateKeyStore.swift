import Foundation
import Security

enum SSHKeyType: String, Codable, CaseIterable {
    case rsa
    case ed25519
    case unknown

    var displayName: String {
        switch self {
        case .rsa: return "RSA"
        case .ed25519: return "ED25519"
        case .unknown: return "Unknown"
        }
    }
}

struct StoredPrivateKeyMetadata: Identifiable, Equatable {
    let id: String
    var label: String
    var keyType: SSHKeyType
    var requiresPassphrase: Bool
    var addedAt: Date
}

enum KeychainStoreError: Error, LocalizedError, Equatable {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidMetadata
    case missingData

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Key not found in Keychain."
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message) (\(status))."
            }
            return "Keychain error (\(status))."
        case .invalidMetadata:
            return "Saved key metadata is invalid."
        case .missingData:
            return "Key data is missing."
        }
    }
}

final class KeychainPrivateKeyStore {
    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = KeychainPrivateKeyStore.defaultServiceName()) {
        self.service = service
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func storePrivateKey(
        data: Data,
        label: String,
        keyType: SSHKeyType,
        requiresPassphrase: Bool
    ) throws -> StoredPrivateKeyMetadata {
        let keyRefId = UUID().uuidString
        let metadata = StoredPrivateKeyMetadata(
            id: keyRefId,
            label: label,
            keyType: keyType,
            requiresPassphrase: requiresPassphrase,
            addedAt: Date()
        )
        let comment = try encodeMetadata(metadata)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyRefId,
            kSecAttrLabel as String: label,
            kSecAttrComment as String: comment,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return metadata
    }

    func loadPrivateKeyData(keyRefId: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyRefId,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            throw KeychainStoreError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainStoreError.missingData
        }
        return data
    }

    func deleteKey(keyRefId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyRefId,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            throw KeychainStoreError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func listKeys() throws -> [StoredPrivateKeyMetadata] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let items = result as? [[String: Any]] else {
            throw KeychainStoreError.invalidMetadata
        }
        let mapped = items.compactMap { item -> StoredPrivateKeyMetadata? in
            guard let keyRefId = item[kSecAttrAccount as String] as? String else {
                return nil
            }
            let label = (item[kSecAttrLabel as String] as? String) ?? "Imported Key"
            let comment = item[kSecAttrComment as String] as? String
            if let comment,
               let payload = decodeMetadata(comment) {
                return StoredPrivateKeyMetadata(
                    id: keyRefId,
                    label: payload.label,
                    keyType: payload.keyType,
                    requiresPassphrase: payload.requiresPassphrase,
                    addedAt: payload.addedAt
                )
            }
            return StoredPrivateKeyMetadata(
                id: keyRefId,
                label: label,
                keyType: .unknown,
                requiresPassphrase: false,
                addedAt: Date.distantPast
            )
        }
        return mapped.sorted { $0.addedAt > $1.addedAt }
    }

    func metadata(keyRefId: String) throws -> StoredPrivateKeyMetadata? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyRefId,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let item = result as? [String: Any] else {
            throw KeychainStoreError.invalidMetadata
        }
        let label = (item[kSecAttrLabel as String] as? String) ?? "Imported Key"
        let comment = item[kSecAttrComment as String] as? String
        if let comment,
           let payload = decodeMetadata(comment) {
            return StoredPrivateKeyMetadata(
                id: keyRefId,
                label: payload.label,
                keyType: payload.keyType,
                requiresPassphrase: payload.requiresPassphrase,
                addedAt: payload.addedAt
            )
        }
        return StoredPrivateKeyMetadata(
            id: keyRefId,
            label: label,
            keyType: .unknown,
            requiresPassphrase: false,
            addedAt: Date.distantPast
        )
    }

    private struct MetadataPayload: Codable {
        let label: String
        let keyType: SSHKeyType
        let requiresPassphrase: Bool
        let addedAt: Date
    }

    private func encodeMetadata(_ metadata: StoredPrivateKeyMetadata) throws -> String {
        let payload = MetadataPayload(
            label: metadata.label,
            keyType: metadata.keyType,
            requiresPassphrase: metadata.requiresPassphrase,
            addedAt: metadata.addedAt
        )
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidMetadata
        }
        return string
    }

    private func decodeMetadata(_ comment: String) -> MetadataPayload? {
        guard let data = comment.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(MetadataPayload.self, from: data)
    }

    private static func defaultServiceName() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "MoshTerminal"
        return "\(bundleId).sshPrivateKey"
    }
}
