import Foundation

final class AppEnvironment: ObservableObject {
    struct Dependencies {
        let hostRepository: HostRepository
        let keyStore: KeychainPrivateKeyStore
        let trustedHostKeyRepository: TrustedHostKeyRepository
        let sshClientFactory: SSHClientFactory
        let appLifecycleService: AppLifecycleService
        let networkPathService: NetworkPathService
    }

    let dependencies: Dependencies

    init() {
        let store = JSONStore()
        let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
        self.dependencies = Dependencies(
            hostRepository: HostRepository(store: store),
            keyStore: KeychainPrivateKeyStore(),
            trustedHostKeyRepository: trustedHostKeyRepository,
            sshClientFactory: DefaultSSHClientFactory.make(repository: trustedHostKeyRepository),
            appLifecycleService: AppLifecycleService(),
            networkPathService: NetworkPathService()
        )
    }
}
