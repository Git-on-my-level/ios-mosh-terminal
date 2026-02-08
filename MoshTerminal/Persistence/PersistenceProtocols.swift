import Foundation

protocol PrivateKeyStoring {
    func loadPrivateKeyData(keyRefId: String) throws -> Data
    func metadata(keyRefId: String) throws -> StoredPrivateKeyMetadata?
}

protocol PrivateKeyListing {
    func listKeys() throws -> [StoredPrivateKeyMetadata]
}

protocol PrivateKeyDeleting {
    func deleteKey(keyRefId: String) throws
}

protocol PrivateKeyImporting {
    func storePrivateKey(data: Data, label: String, keyType: SSHKeyType, requiresPassphrase: Bool) throws -> StoredPrivateKeyMetadata
}

protocol PrivateKeyStoringAndListing: PrivateKeyStoring, PrivateKeyListing {}

protocol PrivateKeyManaging: PrivateKeyStoringAndListing, PrivateKeyDeleting, PrivateKeyImporting {}

protocol HostPersisting {
    func upsert(_ host: HostProfile) async throws
}

protocol HostListing {
    func all() async throws -> [HostProfile]
}

protocol HostDeleting {
    func delete(id: UUID) async throws
}

protocol HostRepositoryProtocol: HostListing, HostDeleting, HostPersisting {}

protocol TrustedHostKeyListing {
    func all() async throws -> [TrustedHostKey]
}

protocol TrustedHostKeyDeleting {
    func delete(hostname: String, port: Int, fingerprint: String) async throws
}

protocol TrustedHostKeyManaging: TrustedHostKeyListing, TrustedHostKeyDeleting {}
