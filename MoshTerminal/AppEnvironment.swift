import Foundation

final class AppEnvironment: ObservableObject {
    struct Dependencies {
        let hostRepository: HostRepository
        let keyStore: KeychainPrivateKeyStore
        let trustedHostKeyRepository: TrustedHostKeyRepository
        let sshClientFactory: SSHClientFactory
        let moshBootstrapper: MoshBootstrapper
        let appLifecycleService: AppLifecycleService
        let networkPathService: NetworkPathService
    }

    let dependencies: Dependencies

    init() {
        let store = JSONStore()
        let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
        let sshClientFactory = DefaultSSHClientFactory.make(repository: trustedHostKeyRepository)
        self.dependencies = Dependencies(
            hostRepository: HostRepository(store: store),
            keyStore: KeychainPrivateKeyStore(),
            trustedHostKeyRepository: trustedHostKeyRepository,
            sshClientFactory: sshClientFactory,
            moshBootstrapper: MoshBootstrapper(sshClientFactory: sshClientFactory),
            appLifecycleService: AppLifecycleService(),
            networkPathService: NetworkPathService()
        )
    }
}
