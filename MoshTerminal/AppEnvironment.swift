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

    init() {
        let store = JSONStore()
        let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
        let sshClientFactory = DefaultSSHClientFactory.make(repository: trustedHostKeyRepository)
        let keyStore = KeychainPrivateKeyStore()
        let moshBootstrapper = MoshBootstrapper(sshClientFactory: sshClientFactory)
        let moshEngineFactory = DefaultMoshEngineFactory.make()
        let appLifecycleService = AppLifecycleService()
        let networkPathService = NetworkPathService()
        let connectionManager = ConnectionManager(
            keyStore: keyStore,
            moshBootstrapper: moshBootstrapper,
            moshEngineFactory: moshEngineFactory,
            appLifecycleService: appLifecycleService,
            networkPathService: networkPathService
        )
        self.dependencies = Dependencies(
            hostRepository: HostRepository(store: store),
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
