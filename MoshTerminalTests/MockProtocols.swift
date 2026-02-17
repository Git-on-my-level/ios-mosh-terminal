import Combine
@testable import MoshTerminal

final class MockAppLifecycleService: AppLifecycleProviding {
    var state: AppLifecycleService.State = .foreground
    let eventsPublisher: AnyPublisher<AppLifecycleService.Event, Never>
    private let eventsSubject = PassthroughSubject<AppLifecycleService.Event, Never>()

    init() {
        eventsPublisher = eventsSubject.eraseToAnyPublisher()
    }

    func simulateForeground() {
        eventsSubject.send(.foreground)
    }

    func simulateBackground() {
        eventsSubject.send(.background)
    }
}

final class MockNetworkPathService: NetworkPathProviding {
    var isSatisfied: Bool = true
    let pathInfoPublisher: AnyPublisher<NetworkPathService.PathInfo, Never>
    private let pathInfoSubject = PassthroughSubject<NetworkPathService.PathInfo, Never>()
    private(set) var startMonitoringCallCount = 0

    init(isSatisfied: Bool = true) {
        self.isSatisfied = isSatisfied
        pathInfoPublisher = pathInfoSubject.eraseToAnyPublisher()
    }

    func simulateNetworkStatus(status: NWPath.Status) {
        pathInfoSubject.send(NetworkPathService.PathInfo(status: status, interfaceType: nil))
    }

    func startMonitoring() {
        startMonitoringCallCount += 1
    }
}

final class MockMoshBootstrapper: MoshBootstrapping {
    var bootstrapResult: Result<MoshBootstrapResult, Error> = .failure(MoshBootstrapError.moshServerMissing)
    var bootstrapCallCount = 0

    func bootstrap(
        host: HostProfile,
        privateKey: Data,
        passphrase: String?,
        hostKeyPrompter: SSHHostKeyPrompting,
        resetManagedSession: Bool
    ) async throws -> MoshBootstrapResult {
        _ = resetManagedSession
        bootstrapCallCount += 1
        return try bootstrapResult.get()
    }
}

final class MockPrivateKeyStore: PrivateKeyManaging {
    var keys: [StoredPrivateKeyMetadata] = []
    var keyData: [String: Data] = [:]
    var loadPrivateKeyDataThrows: Error?
    var metadataResult: [String: StoredPrivateKeyMetadata?] = [:]

    func loadPrivateKeyData(keyRefId: String) throws -> Data {
        if let error = loadPrivateKeyDataThrows {
            throw error
        }
        guard let data = keyData[keyRefId] else {
            throw KeychainStoreError.itemNotFound
        }
        return data
    }

    func metadata(keyRefId: String) throws -> StoredPrivateKeyMetadata? {
        if let result = metadataResult[keyRefId] {
            if let error = result as? Error {
                throw error
            }
            return result
        }
        return keys.first { $0.id == keyRefId }
    }

    func listKeys() throws -> [StoredPrivateKeyMetadata] {
        keys
    }

    func deleteKey(keyRefId: String) throws {
        keys.removeAll { $0.id == keyRefId }
        keyData.removeValue(forKey: keyRefId)
    }
}

final class MockHostRepository: HostRepositoryProtocol {
    var hosts: [HostProfile] = []
    var deleteIdCalls: [UUID] = []
    var upsertCalls: [HostProfile] = []

    func all() async throws -> [HostProfile] {
        hosts
    }

    func delete(id: UUID) async throws {
        deleteIdCalls.append(id)
        hosts.removeAll { $0.id == id }
    }

    func upsert(_ host: HostProfile) async throws {
        upsertCalls.append(host)
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
    }
}

final class MockTrustedHostKeyRepository: TrustedHostKeyManaging {
    var keys: [TrustedHostKey] = []
    var deleteCalls: [(String, Int, String)] = []

    func all() async throws -> [TrustedHostKey] {
        keys
    }

    func delete(hostname: String, port: Int, fingerprint: String) async throws {
        deleteCalls.append((hostname, port, fingerprint))
        keys.removeAll { key in
            key.hostname == hostname && key.port == port && key.fingerprint == fingerprint
        }
    }
}
