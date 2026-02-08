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

struct StoreMigration {
    let fromVersion: Int
    let toVersion: Int
    let migrate: (StoreState) throws -> StoreState
}

final class JSONStore: @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue: DispatchQueue
    private let fileProtectionType: FileProtectionType
    private let excludeFromBackup: Bool

    private static let migrations: [StoreMigration] = [
        StoreMigration(fromVersion: 0, toVersion: 1) { state in
            var migrated = state
            migrated.schemaVersion = 1
            return migrated
        }
    ]

    init(
        fileURL: URL = JSONStore.defaultFileURL(),
        fileProtectionType: FileProtectionType = .completeUnlessOpen,
        excludeFromBackup: Bool = true
    ) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.queue = DispatchQueue(label: "JSONStore.queue")
        self.fileProtectionType = fileProtectionType
        self.excludeFromBackup = excludeFromBackup
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() async throws -> StoreState {
        try await runOnQueue {
            try self.loadUnlocked()
        }
    }

    func save(_ state: StoreState) async throws {
        try await runOnQueue {
            try self.saveUnlocked(state)
        }
    }

    func update<T>(_ transform: @escaping (inout StoreState) throws -> T) async throws -> T {
        try await runOnQueue {
            var state = try self.loadUnlocked()
            let result = try transform(&state)
            try self.saveUnlocked(state)
            return result
        }
    }

    private func loadUnlocked() throws -> StoreState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty()
        }
        let data = try Data(contentsOf: fileURL)
        let state = try decoder.decode(StoreState.self, from: data)
        let migrated = try migrateIfNeeded(state)
        if migrated.schemaVersion != state.schemaVersion {
            try saveUnlocked(migrated)
        }
        return migrated
    }

    private func saveUnlocked(_ state: StoreState) throws {
        var mutableState = state
        mutableState.schemaVersion = StoreState.currentSchemaVersion
        try ensureDirectoryExists()
        let data = try encoder.encode(mutableState)
        try data.write(to: fileURL, options: writeOptions)
        try applyFilePolicies()
    }

    private func migrateIfNeeded(_ state: StoreState) throws -> StoreState {
        if state.schemaVersion == StoreState.currentSchemaVersion {
            return state
        }
        if state.schemaVersion > StoreState.currentSchemaVersion {
            throw StoreError.unsupportedVersion(state.schemaVersion)
        }

        var current = state
        while current.schemaVersion < StoreState.currentSchemaVersion {
            guard let step = Self.migrations.first(where: { $0.fromVersion == current.schemaVersion }) else {
                throw StoreError.unsupportedVersion(current.schemaVersion)
            }
            guard step.toVersion > step.fromVersion else {
                throw StoreError.unsupportedVersion(current.schemaVersion)
            }
            current = try step.migrate(current)
            current.schemaVersion = step.toVersion
        }
        return current
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func applyFilePolicies() throws {
        try FileManager.default.setAttributes([.protectionKey: fileProtectionType], ofItemAtPath: fileURL.path)
        if excludeFromBackup {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = fileURL
            try mutableURL.setResourceValues(values)
        }
    }

    private var writeOptions: Data.WritingOptions {
        var options: Data.WritingOptions = [.atomic]
        switch fileProtectionType {
        case .complete:
            options.insert(.completeFileProtection)
        case .completeUnlessOpen:
            options.insert(.completeFileProtectionUnlessOpen)
        case .completeUntilFirstUserAuthentication:
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        default:
            break
        }
        return options
    }

    private func runOnQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleFolder = Bundle.main.bundleIdentifier ?? "MoshTerminal"
        return baseURL
            .appendingPathComponent(bundleFolder, isDirectory: true)
            .appendingPathComponent("store.json", isDirectory: false)
    }
}

final class HostRepository: @unchecked Sendable {
    private let store: JSONStore

    init(store: JSONStore) {
        self.store = store
    }

    func all() async throws -> [HostProfile] {
        try await store.load().hosts
    }

    func upsert(_ host: HostProfile) async throws {
        try await store.update { state in
            if let index = state.hosts.firstIndex(where: { $0.id == host.id }) {
                state.hosts[index] = host
            } else {
                state.hosts.append(host)
            }
        }
    }

    func delete(id: UUID) async throws {
        try await store.update { state in
            state.hosts.removeAll { $0.id == id }
        }
    }

    func replaceAll(_ hosts: [HostProfile]) async throws {
        try await store.update { state in
            state.hosts = hosts
        }
    }
}

extension HostRepository: HostRepositoryProtocol {}

final class TrustedHostKeyRepository: @unchecked Sendable {
    private let store: JSONStore

    init(store: JSONStore) {
        self.store = store
    }

    func all() async throws -> [TrustedHostKey] {
        let keys = try await store.load().trustedHostKeys
        return keys.sorted { lhs, rhs in
            if lhs.hostname != rhs.hostname { return lhs.hostname < rhs.hostname }
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            if lhs.fingerprint != rhs.fingerprint { return lhs.fingerprint < rhs.fingerprint }
            return lhs.addedAt < rhs.addedAt
        }
    }

    func upsert(_ key: TrustedHostKey) async throws {
        try await store.update { state in
            if let index = state.trustedHostKeys.firstIndex(where: { existing in
                existing.hostname == key.hostname && existing.port == key.port && existing.fingerprint == key.fingerprint
            }) {
                state.trustedHostKeys[index] = key
            } else {
                state.trustedHostKeys.append(key)
            }
        }
    }

    func delete(hostname: String, port: Int, fingerprint: String) async throws {
        try await store.update { state in
            state.trustedHostKeys.removeAll { key in
                key.hostname == hostname && key.port == port && key.fingerprint == fingerprint
            }
        }
    }

    func keys(for hostname: String, port: Int) async throws -> [TrustedHostKey] {
        let keys = try await store.load().trustedHostKeys
        return keys.filter { $0.hostname == hostname && $0.port == port }
    }
}

extension TrustedHostKeyRepository: TrustedHostKeyManaging {}
