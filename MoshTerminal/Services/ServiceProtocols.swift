import Foundation
import Combine

protocol AppLifecycleProviding: AnyObject {
    var state: AppLifecycleService.State { get }
    var eventsPublisher: AnyPublisher<AppLifecycleService.Event, Never> { get }
}

protocol NetworkPathProviding: AnyObject {
    var pathInfoPublisher: AnyPublisher<NetworkPathService.PathInfo, Never> { get }
    var isSatisfied: Bool { get }
    func startMonitoring()
}

extension NetworkPathProviding {
    func startMonitoring() {}
}

protocol MoshBootstrapping {
    func bootstrap(
        host: HostProfile,
        privateKey: Data,
        passphrase: String?,
        hostKeyPrompter: SSHHostKeyPrompting,
        resetManagedSession: Bool
    ) async throws -> MoshBootstrapResult
}
