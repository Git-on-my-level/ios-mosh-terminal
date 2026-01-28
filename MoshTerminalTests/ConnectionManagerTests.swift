import Combine
import Network
import XCTest
@testable import MoshTerminal

@MainActor
final class ConnectionManagerTests: XCTestCase {
    func testConnectTransitionsToConnected() async {
        let host = makeHost()
        let bootstrapper = TestBootstrapper(results: [.success(makeConnectInfo())])
        let engineFactory = TestEngineFactory(engines: [TestMoshEngine(behavior: .autoConnect)])
        let manager = makeManager(bootstrapper: bootstrapper, engineFactory: engineFactory)

        manager.connect(
            host: host,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        XCTAssertEqual(bootstrapper.callCount, 1)
        XCTAssertEqual(engineFactory.createdEngines.first?.startCalls, 1)
    }

    func testReconnectIgnoresRepeatedTriggersWhileConnecting() async {
        let host = makeHost()
        let bootstrapper = TestBootstrapper(results: [])
        let engineFactory = TestEngineFactory(engines: [TestMoshEngine(behavior: .autoConnect)])
        let lifecycle = TestAppLifecycleService()
        let network = TestNetworkPathService(status: .satisfied)
        let manager = makeManager(
            bootstrapper: bootstrapper,
            engineFactory: engineFactory,
            lifecycle: lifecycle,
            network: network
        )

        manager.connect(
            host: host,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        await waitUntil { bootstrapper.isWaiting }
        lifecycle.send(.foreground)
        network.setStatus(.satisfied)
        lifecycle.send(.foreground)

        XCTAssertEqual(bootstrapper.callCount, 1)

        bootstrapper.resume(with: .success(makeConnectInfo()))
        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }
    }

    func testReconnectAttemptsResumeThenBootstrapsAfterTimeout() async {
        let host = makeHost()
        let connectInfoA = makeConnectInfo(port: 60001)
        let connectInfoB = makeConnectInfo(port: 60002)
        let bootstrapper = TestBootstrapper(results: [.success(connectInfoA), .success(connectInfoB)])
        let engines: [TestMoshEngine] = [
            TestMoshEngine(behavior: .autoConnect),
            TestMoshEngine(behavior: .neverConnect),
            TestMoshEngine(behavior: .autoConnect)
        ]
        let engineFactory = TestEngineFactory(engines: engines)
        let manager = makeManager(
            bootstrapper: bootstrapper,
            engineFactory: engineFactory,
            connectionTimeoutNanoseconds: 50_000_000
        )

        manager.connect(
            host: host,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        engines[0].emit(.disconnected)

        await waitUntil { bootstrapper.callCount >= 2 }
        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        XCTAssertEqual(bootstrapper.callCount, 2)
        XCTAssertEqual(engineFactory.createdEngines.count, 3)
    }

    func testDisconnectDoesNotTriggerReconnectOrFailure() async {
        let host = makeHost()
        let bootstrapper = TestBootstrapper(results: [.success(makeConnectInfo())])
        let engines = [
            TestMoshEngine(behavior: .autoConnect, stopState: .disconnected),
            TestMoshEngine(behavior: .autoConnect, stopState: .disconnected)
        ]
        let engineFactory = TestEngineFactory(engines: engines)
        let manager = makeManager(bootstrapper: bootstrapper, engineFactory: engineFactory)

        manager.connect(
            host: host,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        await manager.disconnect(clearSession: false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.failure)
        XCTAssertEqual(engineFactory.createdEngines.count, 1)
        XCTAssertEqual(bootstrapper.callCount, 1)
    }

    private func makeManager(
        bootstrapper: TestBootstrapper,
        engineFactory: TestEngineFactory,
        lifecycle: TestAppLifecycleService = TestAppLifecycleService(),
        network: TestNetworkPathService = TestNetworkPathService(status: .satisfied),
        connectionTimeoutNanoseconds: UInt64 = 200_000_000
    ) -> ConnectionManager {
        ConnectionManager(
            keyStore: TestKeyStore(),
            moshBootstrapper: bootstrapper,
            moshEngineFactory: { engineFactory.make() },
            appLifecycleService: lifecycle,
            networkPathService: network,
            connectionTimeoutNanoseconds: connectionTimeoutNanoseconds
        )
    }

    private func makeHost() -> HostProfile {
        HostProfile(
            displayName: "Test",
            hostname: "example.com",
            username: "mosh",
            sshPort: 22,
            keyRefId: "key-1",
            lastConnectedAt: nil
        )
    }

    private func makeConnectInfo(port: Int = 60000) -> MoshConnectInfo {
        MoshConnectInfo(udpPort: port, sessionKey: "abc123=", serverAddress: "example.com")
    }

    private func awaitState(
        _ manager: ConnectionManager,
        matches: @escaping (ConnectionManager.State) -> Bool,
        timeout: TimeInterval = 1.5
    ) async {
        if matches(manager.state) { return }
        let expectation = expectation(description: "state change")
        var cancellable: AnyCancellable?
        cancellable = manager.$state.sink { state in
            if matches(state) {
                expectation.fulfill()
            }
        }
        await fulfillment(of: [expectation], timeout: timeout)
        cancellable?.cancel()
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 1.5
    ) async {
        let start = Date()
        while !condition() && Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition())
    }
}

private final class TestAppLifecycleService: AppLifecycleProviding {
    var state: AppLifecycleService.State = .foreground
    private let subject = PassthroughSubject<AppLifecycleService.Event, Never>()

    var eventsPublisher: AnyPublisher<AppLifecycleService.Event, Never> {
        subject.eraseToAnyPublisher()
    }

    func send(_ event: AppLifecycleService.Event) {
        switch event {
        case .foreground:
            state = .foreground
        case .background:
            state = .background
        }
        subject.send(event)
    }
}

private final class TestNetworkPathService: NetworkPathProviding {
    @Published private var pathInfo: NetworkPathService.PathInfo

    init(status: NWPath.Status) {
        self.pathInfo = NetworkPathService.PathInfo(status: status, interfaceType: .wifi)
    }

    var pathInfoPublisher: AnyPublisher<NetworkPathService.PathInfo, Never> {
        $pathInfo.eraseToAnyPublisher()
    }

    var isSatisfied: Bool {
        pathInfo.status == .satisfied
    }

    func setStatus(_ status: NWPath.Status) {
        pathInfo = NetworkPathService.PathInfo(status: status, interfaceType: pathInfo.interfaceType)
    }
}

private struct TestKeyStore: PrivateKeyStoring {
    func loadPrivateKeyData(keyRefId: String) throws -> Data {
        Data("key".utf8)
    }
}

private final class TestBootstrapper: MoshBootstrapping {
    var results: [Result<MoshConnectInfo, Error>]
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<MoshConnectInfo, Error>?

    init(results: [Result<MoshConnectInfo, Error>]) {
        self.results = results
    }

    var isWaiting: Bool {
        continuation != nil
    }

    func resume(with result: Result<MoshConnectInfo, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func bootstrap(
        host: HostProfile,
        privateKey: Data,
        passphrase: String?,
        hostKeyPrompter: SSHHostKeyPrompting
    ) async throws -> MoshConnectInfo {
        callCount += 1
        if !results.isEmpty {
            return try results.removeFirst().get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private final class TestEngineFactory: @unchecked Sendable {
    private(set) var createdEngines: [TestMoshEngine] = []
    private var engines: [TestMoshEngine]

    init(engines: [TestMoshEngine]) {
        self.engines = engines
    }

    func make() -> MoshEngine {
        let engine = engines.removeFirst()
        createdEngines.append(engine)
        return engine
    }
}

private final class TestMoshEngine: MoshEngine, @unchecked Sendable {
    enum Behavior {
        case autoConnect
        case neverConnect
        case failStart
    }

    var onOutput: ((Data) -> Void)?
    var onStateChange: ((MoshEngineState) -> Void)?

    let behavior: Behavior
    let stopState: MoshEngineState
    private(set) var startCalls = 0

    init(behavior: Behavior, stopState: MoshEngineState = .idle) {
        self.behavior = behavior
        self.stopState = stopState
    }

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws {
        startCalls += 1
        emit(.starting)
        switch behavior {
        case .autoConnect:
            emit(.connected)
        case .neverConnect:
            break
        case .failStart:
            throw MoshEngineError.startFailed(message: "fail")
        }
    }

    func sendInput(_ bytes: Data) async {}
    func updateTerminalSize(cols: Int, rows: Int) async {}

    func stop() async {
        emit(stopState)
    }

    func emit(_ state: MoshEngineState) {
        onStateChange?(state)
    }
}
