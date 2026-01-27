import Foundation

final class AppEnvironment: ObservableObject {
    struct Dependencies {
        let hostRepository: HostRepository
        let keyStore: KeychainPrivateKeyStore
        let appLifecycleService: AppLifecycleService
        let networkPathService: NetworkPathService
    }

    let dependencies: Dependencies

    init() {
        let store = JSONStore()
        self.dependencies = Dependencies(
            hostRepository: HostRepository(store: store),
            keyStore: KeychainPrivateKeyStore(),
            appLifecycleService: AppLifecycleService(),
            networkPathService: NetworkPathService()
        )
    }
}
