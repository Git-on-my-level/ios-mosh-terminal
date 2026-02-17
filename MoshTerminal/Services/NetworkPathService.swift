import Combine
import Foundation
import Network

@MainActor
final class NetworkPathService: ObservableObject {
    struct PathInfo: Equatable {
        let status: NWPath.Status
        let interfaceType: NWInterface.InterfaceType?
    }

    @Published private(set) var pathInfo: PathInfo

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var hasStartedMonitoring = false

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(label: "NetworkPathService")
    ) {
        self.monitor = monitor
        self.queue = queue
        let currentPath = monitor.currentPath
        self.pathInfo = PathInfo(
            status: currentPath.status,
            interfaceType: Self.interfaceType(from: currentPath)
        )

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let info = PathInfo(status: path.status, interfaceType: Self.interfaceType(from: path))
            Task { @MainActor in
                self.pathInfo = info
            }
        }
    }

    deinit {
        monitor.cancel()
    }

    func startMonitoring() {
        guard !hasStartedMonitoring else { return }
        hasStartedMonitoring = true

        Task { @MainActor in
            StartupDiagnostics.shared.incrementNetworkMonitorStart()
        }
        monitor.start(queue: queue)
    }

    var isSatisfied: Bool {
        pathInfo.status == .satisfied
    }

    nonisolated static func interfaceType(from path: NWPath) -> NWInterface.InterfaceType? {
        let interfaceTypes: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .loopback, .other]
        for interfaceType in interfaceTypes where path.usesInterfaceType(interfaceType) {
            return interfaceType
        }
        return nil
    }
}

@MainActor
extension NetworkPathService: NetworkPathProviding {
    var pathInfoPublisher: AnyPublisher<PathInfo, Never> {
        $pathInfo.eraseToAnyPublisher()
    }
}
