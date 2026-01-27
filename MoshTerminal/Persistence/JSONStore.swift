import Foundation

enum StoreError: Error, Equatable {
    case unsupportedVersion(Int)
}

struct StoreState: Codable, Equatable {
    var schemaVersion: Int
    var hosts: [HostProfile]
    var trustedHostKeys: [TrustedHostKey]

    static let currentSchemaVersion = 1

    static func empty() -> StoreState {
        StoreState(schemaVersion: currentSchemaVersion, hosts: [], trustedHostKeys: [])
    }
}

final class JSONStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = JSONStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> StoreState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty()
        }
        let data = try Data(contentsOf: fileURL)
        let state = try decoder.decode(StoreState.self, from: data)
        guard state.schemaVersion == StoreState.currentSchemaVersion else {
            throw StoreError.unsupportedVersion(state.schemaVersion)
        }
        return state
    }

    func save(_ state: StoreState) throws {
        var mutableState = state
        mutableState.schemaVersion = StoreState.currentSchemaVersion
        try ensureDirectoryExists()
        let data = try encoder.encode(mutableState)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleFolder = Bundle.main.bundleIdentifier ?? "MoshTerminal"
        return baseURL
            .appendingPathComponent(bundleFolder, isDirectory: true)
            .appendingPathComponent("store.json", isDirectory: false)
    }
}

final class HostRepository {
    private let store: JSONStore

    init(store: JSONStore) {
        self.store = store
    }

    func all() throws -> [HostProfile] {
        try store.load().hosts
    }

    func upsert(_ host: HostProfile) throws {
        var state = try store.load()
        if let index = state.hosts.firstIndex(where: { $0.id == host.id }) {
            state.hosts[index] = host
        } else {
            state.hosts.append(host)
        }
        try store.save(state)
    }

    func delete(id: UUID) throws {
        var state = try store.load()
        state.hosts.removeAll { $0.id == id }
        try store.save(state)
    }

    func replaceAll(_ hosts: [HostProfile]) throws {
        var state = try store.load()
        state.hosts = hosts
        try store.save(state)
    }
}

final class TrustedHostKeyRepository {
    private let store: JSONStore

    init(store: JSONStore) {
        self.store = store
    }

    func all() throws -> [TrustedHostKey] {
        let keys = try store.load().trustedHostKeys
        return keys.sorted { lhs, rhs in
            if lhs.hostname != rhs.hostname { return lhs.hostname < rhs.hostname }
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            if lhs.fingerprint != rhs.fingerprint { return lhs.fingerprint < rhs.fingerprint }
            return lhs.addedAt < rhs.addedAt
        }
    }

    func upsert(_ key: TrustedHostKey) throws {
        var state = try store.load()
        if let index = state.trustedHostKeys.firstIndex(where: { existing in
            existing.hostname == key.hostname && existing.port == key.port && existing.fingerprint == key.fingerprint
        }) {
            state.trustedHostKeys[index] = key
        } else {
            state.trustedHostKeys.append(key)
        }
        try store.save(state)
    }

    func delete(hostname: String, port: Int, fingerprint: String) throws {
        var state = try store.load()
        state.trustedHostKeys.removeAll { key in
            key.hostname == hostname && key.port == port && key.fingerprint == fingerprint
        }
        try store.save(state)
    }

    func keys(for hostname: String, port: Int) throws -> [TrustedHostKey] {
        let keys = try store.load().trustedHostKeys
        return keys.filter { $0.hostname == hostname && $0.port == port }
    }
}
