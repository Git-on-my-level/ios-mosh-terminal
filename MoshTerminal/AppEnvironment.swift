import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    struct Dependencies {
        let hostRepository: HostRepository
        let keyStore: KeychainPrivateKeyStore
        let trustedHostKeyRepository: TrustedHostKeyRepository
        let sshClientFactory: SSHClientFactory
        let moshBootstrapper: MoshBootstrapper
        let moshEngineFactory: MoshEngineFactory
        let appLifecycleService: AppLifecycleService
        let networkPathService: NetworkPathService
        let connectionManager: ConnectionManager
    }

    let dependencies: Dependencies

    init(dependencies: Dependencies) {
        StartupDiagnostics.shared.markAppEnvironmentInitStart()
        self.dependencies = dependencies
        StartupDiagnostics.shared.markAppEnvironmentInitEnd()
    }

    init() {
        StartupDiagnostics.shared.markAppEnvironmentInitStart()
        let store: JSONStore
        if ProcessInfo.processInfo.environment["MOSH_EPHEMERAL_STORE"] == "1" {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("moshterminal-store.json")
            store = JSONStore(fileURL: tempURL, fileProtectionType: .complete, excludeFromBackup: false)
        } else {
            store = JSONStore()
        }
        let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
        let sshClientFactory = DefaultSSHClientFactory.make(repository: trustedHostKeyRepository)
        let keyStore = KeychainPrivateKeyStore()
        let moshBootstrapper = MoshBootstrapper(sshClientFactory: sshClientFactory)
        let moshEngineFactory = DefaultMoshEngineFactory.make()
        let appLifecycleService = AppLifecycleService()
        let networkPathService = NetworkPathService()
        let hostRepository = HostRepository(store: store)
        let connectionManager = ConnectionManager(
            keyStore: keyStore,
            hostRepository: hostRepository,
            moshBootstrapper: moshBootstrapper,
            moshEngineFactory: moshEngineFactory,
            appLifecycleService: appLifecycleService,
            networkPathService: networkPathService
        )
        self.dependencies = Dependencies(
            hostRepository: hostRepository,
            keyStore: keyStore,
            trustedHostKeyRepository: trustedHostKeyRepository,
            sshClientFactory: sshClientFactory,
            moshBootstrapper: moshBootstrapper,
            moshEngineFactory: moshEngineFactory,
            appLifecycleService: appLifecycleService,
            networkPathService: networkPathService,
            connectionManager: connectionManager
        )
        StartupDiagnostics.shared.markAppEnvironmentInitEnd()
    }

    static func makePreviewDependencies() -> Dependencies {
        let store = JSONStore()
        let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
        let sshClientFactory = DefaultSSHClientFactory.make(repository: trustedHostKeyRepository)
        let keyStore = KeychainPrivateKeyStore()
        let moshBootstrapper = MoshBootstrapper(sshClientFactory: sshClientFactory)
        let moshEngineFactory: MoshEngineFactory = { LoopbackMoshEngine() }
        let appLifecycleService = AppLifecycleService()
        let networkPathService = NetworkPathService()
        let hostRepository = HostRepository(store: store)
        let connectionManager = ConnectionManager(
            keyStore: keyStore,
            hostRepository: hostRepository,
            moshBootstrapper: moshBootstrapper,
            moshEngineFactory: moshEngineFactory,
            appLifecycleService: appLifecycleService,
            networkPathService: networkPathService
        )
        return Dependencies(
            hostRepository: hostRepository,
            keyStore: keyStore,
            trustedHostKeyRepository: trustedHostKeyRepository,
            sshClientFactory: sshClientFactory,
            moshBootstrapper: moshBootstrapper,
            moshEngineFactory: moshEngineFactory,
            appLifecycleService: appLifecycleService,
            networkPathService: networkPathService,
            connectionManager: connectionManager
        )
    }
}
