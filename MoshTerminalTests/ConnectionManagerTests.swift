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

        await waitUntil(bootstrapper.isWaiting)
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

        await waitUntil(bootstrapper.callCount >= 2)
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

        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        await manager.disconnect(clearSession: false)
        lifecycle.send(.foreground)
        network.setStatus(.satisfied)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.failure)
        XCTAssertEqual(engineFactory.createdEngines.count, 1)
        XCTAssertEqual(bootstrapper.callCount, 1)
    }

    func testForegroundReconnectSkipsHostsThatWereNeverConnected() async {
        let hostA = makeHost(name: "A", hostname: "a.example.com", keyRefId: "key-a")
        let hostB = makeHost(name: "B", hostname: "b.example.com", keyRefId: "key-b")
        let bootstrapper = TestBootstrapper(results: [.success(makeConnectInfo())])
        let engineFactory = TestEngineFactory(engines: [
            TestMoshEngine(behavior: .autoConnect),
            TestMoshEngine(behavior: .autoConnect)
        ])
        let lifecycle = TestAppLifecycleService()
        let network = TestNetworkPathService(status: .satisfied)
        let manager = makeManager(
            bootstrapper: bootstrapper,
            engineFactory: engineFactory,
            lifecycle: lifecycle,
            network: network
        )

        _ = manager.controller(for: hostB)

        manager.connect(
            host: hostA,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitHostState(manager, hostId: hostA.id) { state in
            if case .connected = state { return true }
            return false
        }

        lifecycle.send(.background)
        await awaitHostState(manager, hostId: hostA.id) { state in
            if case .disconnected = state { return true }
            return false
        }

        lifecycle.send(.foreground)
        await awaitHostState(manager, hostId: hostA.id) { state in
            if case .connected = state { return true }
            return false
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(bootstrapper.callCount, 1)
        XCTAssertEqual(engineFactory.createdEngines.count, 2)
        XCTAssertEqual(manager.state(for: hostB.id), .disconnected)
        XCTAssertNil(manager.failure(for: hostB.id))
    }

    func testBackgroundMarksDisconnectedWithoutFailureAndReconnectsOnForeground() async {
        let host = makeHost()
        let bootstrapper = TestBootstrapper(results: [.success(makeConnectInfo())])
        let engines = [
            TestMoshEngine(behavior: .autoConnect),
            TestMoshEngine(behavior: .autoConnect)
        ]
        let engineFactory = TestEngineFactory(engines: engines)
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

        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        lifecycle.send(.background)

        await awaitState(manager) { state in
            if case .disconnected = state { return true }
            return false
        }

        XCTAssertNil(manager.failure)

        lifecycle.send(.foreground)

        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        XCTAssertEqual(engineFactory.createdEngines.count, 2)
        XCTAssertEqual(bootstrapper.callCount, 1)
    }

    func testConnectUpdatesLastConnectedAt() async {
        let host = makeHost()
        let bootstrapper = TestBootstrapper(results: [.success(makeConnectInfo())])
        let engineFactory = TestEngineFactory(engines: [TestMoshEngine(behavior: .autoConnect)])
        let hostRepository = TestHostRepository()
        let manager = makeManager(
            bootstrapper: bootstrapper,
            engineFactory: engineFactory,
            hostRepository: hostRepository
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

        await waitUntil(!hostRepository.upsertedHosts.isEmpty)

        let updatedHost = hostRepository.upsertedHosts.last
        XCTAssertEqual(updatedHost?.id, host.id)
        XCTAssertNotNil(updatedHost?.lastConnectedAt)
    }

    func testControllerForHostReusesActiveController() async {
        let host = makeHost()
        let bootstrapper = TestBootstrapper(results: [.success(makeConnectInfo())])
        let engineFactory = TestEngineFactory(engines: [TestMoshEngine(behavior: .autoConnect)])
        let manager = makeManager(bootstrapper: bootstrapper, engineFactory: engineFactory)
        let controller = manager.controller(for: host)

        manager.connect(
            host: host,
            controller: controller,
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        let reused = manager.controller(for: host)
        XCTAssertTrue(reused === controller)
    }

    func testControllerForHostResetsAfterClearSessionDisconnect() async {
        let host = makeHost()
        let bootstrapper = TestBootstrapper(results: [.success(makeConnectInfo())])
        let engineFactory = TestEngineFactory(engines: [TestMoshEngine(behavior: .autoConnect)])
        let manager = makeManager(bootstrapper: bootstrapper, engineFactory: engineFactory)
        let controller = manager.controller(for: host)

        manager.connect(
            host: host,
            controller: controller,
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        await awaitState(manager) { state in
            if case .connected = state { return true }
            return false
        }

        await manager.disconnect(clearSession: true)

        let refreshed = manager.controller(for: host)
        XCTAssertFalse(refreshed === controller)
    }

    func testMultipleHostsCanConnectConcurrentlyWithoutStateBleed() async {
        let hostA = makeHost(name: "A", hostname: "a.example.com", keyRefId: "key-a")
        let hostB = makeHost(name: "B", hostname: "b.example.com", keyRefId: "key-b")
        let bootstrapper = TestBootstrapper(results: [
            .success(makeConnectInfo(port: 61001)),
            .success(makeConnectInfo(port: 61002))
        ])
        let engineFactory = TestEngineFactory(engines: [
            TestMoshEngine(behavior: .autoConnect),
            TestMoshEngine(behavior: .autoConnect)
        ])
        let manager = makeManager(bootstrapper: bootstrapper, engineFactory: engineFactory)

        manager.connect(
            host: hostA,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitHostState(manager, hostId: hostA.id) { state in
            if case .connected = state { return true }
            return false
        }

        manager.connect(
            host: hostB,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitHostState(manager, hostId: hostB.id) { state in
            if case .connected = state { return true }
            return false
        }

        XCTAssertEqual(manager.state(for: hostA.id), .connected)
        XCTAssertEqual(manager.state(for: hostB.id), .connected)
        XCTAssertEqual(bootstrapper.callCount, 2)
        XCTAssertEqual(engineFactory.createdEngines.count, 2)
    }

    func testDisconnectingOneHostDoesNotImpactOtherHostSession() async {
        let hostA = makeHost(name: "A", hostname: "a.example.com", keyRefId: "key-a")
        let hostB = makeHost(name: "B", hostname: "b.example.com", keyRefId: "key-b")
        let bootstrapper = TestBootstrapper(results: [
            .success(makeConnectInfo(port: 62001)),
            .success(makeConnectInfo(port: 62002))
        ])
        let engineFactory = TestEngineFactory(engines: [
            TestMoshEngine(behavior: .autoConnect),
            TestMoshEngine(behavior: .autoConnect)
        ])
        let manager = makeManager(bootstrapper: bootstrapper, engineFactory: engineFactory)

        manager.connect(
            host: hostA,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitHostState(manager, hostId: hostA.id) { state in
            if case .connected = state { return true }
            return false
        }

        manager.connect(
            host: hostB,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitHostState(manager, hostId: hostB.id) { state in
            if case .connected = state { return true }
            return false
        }

        await manager.disconnect(hostId: hostB.id, clearSession: true)

        XCTAssertEqual(manager.state(for: hostA.id), .connected)
        XCTAssertEqual(manager.state(for: hostB.id), .idle)
        XCTAssertNil(manager.failure(for: hostA.id))
        XCTAssertNil(manager.failure(for: hostB.id))
    }

    func testFailureIsScopedToFailingHostOnly() async {
        let hostA = makeHost(name: "A", hostname: "a.example.com", keyRefId: "key-a")
        let hostB = makeHost(name: "B", hostname: "b.example.com", keyRefId: "key-b")
        let bootstrapper = TestBootstrapper(results: [
            .success(makeConnectInfo(port: 63001)),
            .success(makeConnectInfo(port: 63002))
        ])
        let engineFactory = TestEngineFactory(engines: [
            TestMoshEngine(behavior: .autoConnect),
            TestMoshEngine(behavior: .failStart)
        ])
        let manager = makeManager(bootstrapper: bootstrapper, engineFactory: engineFactory)

        manager.connect(
            host: hostA,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitHostState(manager, hostId: hostA.id) { state in
            if case .connected = state { return true }
            return false
        }

        manager.connect(
            host: hostB,
            controller: TerminalSessionController(),
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )
        await awaitHostState(manager, hostId: hostB.id) { state in
            if case .failed = state { return true }
            return false
        }

        XCTAssertEqual(manager.state(for: hostA.id), .connected)
        XCTAssertNil(manager.failure(for: hostA.id))
        XCTAssertNotNil(manager.failure(for: hostB.id))
    }

    private func makeManager(
        bootstrapper: TestBootstrapper,
        engineFactory: TestEngineFactory,
        lifecycle: TestAppLifecycleService = TestAppLifecycleService(),
        network: TestNetworkPathService = TestNetworkPathService(status: .satisfied),
        connectionTimeoutNanoseconds: UInt64 = 200_000_000,
        hostRepository: TestHostRepository = TestHostRepository()
    ) -> ConnectionManager {
        ConnectionManager(
            keyStore: TestKeyStore(),
            hostRepository: hostRepository,
            moshBootstrapper: bootstrapper,
            moshEngineFactory: { engineFactory.make() },
            appLifecycleService: lifecycle,
            networkPathService: network,
            connectionTimeoutNanoseconds: connectionTimeoutNanoseconds
        )
    }

    private func makeHost() -> HostProfile {
        makeHost(name: "Test", hostname: "example.com", keyRefId: "key-1")
    }

    private func makeHost(name: String, hostname: String, keyRefId: String) -> HostProfile {
        HostProfile(
            displayName: name,
            hostname: hostname,
            username: "mosh",
            sshPort: 22,
            keyRefId: keyRefId,
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
        expectation.assertForOverFulfill = false
        var cancellable: AnyCancellable?
        cancellable = manager.$state.sink { state in
            if matches(state) {
                expectation.fulfill()
            }
        }
        await fulfillment(of: [expectation], timeout: timeout)
        cancellable?.cancel()
    }

    private func awaitHostState(
        _ manager: ConnectionManager,
        hostId: UUID,
        matches: @escaping (ConnectionManager.State) -> Bool,
        timeout: TimeInterval = 1.5
    ) async {
        if matches(manager.state(for: hostId)) { return }
        let expectation = expectation(description: "host state change")
        expectation.assertForOverFulfill = false
        var cancellable: AnyCancellable?
        cancellable = manager.$statesByHostId.sink { states in
            let hostState = states[hostId] ?? .idle
            if matches(hostState) {
                expectation.fulfill()
            }
        }
        await fulfillment(of: [expectation], timeout: timeout)
        cancellable?.cancel()
    }

    private func waitUntil(
        _ condition: @autoclosure @escaping () -> Bool,
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

    func metadata(keyRefId: String) throws -> StoredPrivateKeyMetadata? {
        StoredPrivateKeyMetadata(
            id: keyRefId,
            label: "Test Key",
            keyType: .rsa,
            requiresPassphrase: false,
            addedAt: Date()
        )
    }
}

private final class TestHostRepository: HostPersisting {
    private(set) var upsertedHosts: [HostProfile] = []

    func upsert(_ host: HostProfile) async throws {
        upsertedHosts.append(host)
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

    var onOutput: (@Sendable (Data) -> Void)?
    var onRemoteResize: (@Sendable (TerminalSize) -> Void)?
    var onStateChange: (@Sendable (MoshEngineState) -> Void)?

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
