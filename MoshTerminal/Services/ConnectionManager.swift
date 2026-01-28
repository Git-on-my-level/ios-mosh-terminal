import Combine
import Foundation

protocol AppLifecycleProviding: AnyObject {
    var state: AppLifecycleService.State { get }
    var eventsPublisher: AnyPublisher<AppLifecycleService.Event, Never> { get }
}

protocol NetworkPathProviding: AnyObject {
    var pathInfoPublisher: AnyPublisher<NetworkPathService.PathInfo, Never> { get }
    var isSatisfied: Bool { get }
}

protocol MoshBootstrapping {
    func bootstrap(
        host: HostProfile,
        privateKey: Data,
        passphrase: String?,
        hostKeyPrompter: SSHHostKeyPrompting
    ) async throws -> MoshConnectInfo
}

protocol PrivateKeyStoring {
    func loadPrivateKeyData(keyRefId: String) throws -> Data
    func metadata(keyRefId: String) throws -> StoredPrivateKeyMetadata?
}

protocol HostPersisting {
    func upsert(_ host: HostProfile) throws
}

extension AppLifecycleService: AppLifecycleProviding {
    var eventsPublisher: AnyPublisher<AppLifecycleService.Event, Never> {
        events.eraseToAnyPublisher()
    }
}

extension NetworkPathService: NetworkPathProviding {
    var pathInfoPublisher: AnyPublisher<NetworkPathService.PathInfo, Never> {
        $pathInfo.eraseToAnyPublisher()
    }
}

extension MoshBootstrapper: MoshBootstrapping {}

extension KeychainPrivateKeyStore: PrivateKeyStoring {}

extension HostRepository: HostPersisting {}

@MainActor
final class ConnectionManager: ObservableObject {
    enum State: Equatable {
        case idle
        case disconnected
        case bootstrappingSSH
        case connectingUDP
        case connected
        case reconnecting
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var activeHostId: UUID?
    @Published private(set) var failure: ConnectionFailure?

    private let keyStore: PrivateKeyStoring
    private let hostRepository: HostPersisting
    private let moshBootstrapper: MoshBootstrapping
    private let moshEngineFactory: MoshEngineFactory
    private let appLifecycleService: AppLifecycleProviding
    private let networkPathService: NetworkPathProviding
    private let connectionTimeoutNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void

    private var activeHost: HostProfile?
    private var hostKeyPrompter: SSHHostKeyPrompting = SSHHostKeyPrompt.denyAll
    private var passphrasePrompter: SSHKeyPassphrasePrompting = SSHKeyPassphrasePrompt.denyAll
    private weak var controller: TerminalSessionController?

    private var engine: MoshEngine?
    private var lastConnectInfo: MoshConnectInfo?

    private var connectTask: Task<Void, Never>?
    private var connectToken = UUID()

    private var connectWaiterToken: UUID?
    private var connectWaiter: CheckedContinuation<Bool, Never>?

    private var cancellables: Set<AnyCancellable> = []
    private var reconnectBackoff: ReconnectBackoffState

    init(
        keyStore: PrivateKeyStoring,
        hostRepository: HostPersisting,
        moshBootstrapper: MoshBootstrapping,
        moshEngineFactory: @escaping MoshEngineFactory,
        appLifecycleService: AppLifecycleProviding,
        networkPathService: NetworkPathProviding,
        connectionTimeoutNanoseconds: UInt64 = 5_000_000_000,
        reconnectBackoffPolicy: ReconnectBackoffPolicy = .default,
        reconnectRandomUnit: @escaping () -> Double = { Double.random(in: 0...1) },
        sleep: @Sendable @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.keyStore = keyStore
        self.hostRepository = hostRepository
        self.moshBootstrapper = moshBootstrapper
        self.moshEngineFactory = moshEngineFactory
        self.appLifecycleService = appLifecycleService
        self.networkPathService = networkPathService
        self.connectionTimeoutNanoseconds = connectionTimeoutNanoseconds
        self.reconnectBackoff = ReconnectBackoffState(
            policy: reconnectBackoffPolicy,
            randomUnit: reconnectRandomUnit
        )
        self.sleep = sleep

        appLifecycleService.eventsPublisher
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .foreground:
                    self.requestReconnect(reason: .foreground)
                case .background:
                    Task { await self.handleBackground() }
                }
            }
            .store(in: &cancellables)

        networkPathService.pathInfoPublisher
            .removeDuplicates()
            .sink { [weak self] info in
                guard let self else { return }
                if info.status == .satisfied {
                    self.requestReconnect(reason: .networkSatisfied)
                }
            }
            .store(in: &cancellables)
    }

    func connect(
        host: HostProfile,
        controller: TerminalSessionController,
        hostKeyPrompter: SSHHostKeyPrompting,
        passphrasePrompter: SSHKeyPassphrasePrompting = SSHKeyPassphrasePrompt.denyAll
    ) {
        self.activeHost = host
        self.activeHostId = host.id
        self.controller = controller
        self.hostKeyPrompter = hostKeyPrompter
        self.passphrasePrompter = passphrasePrompter
        failure = nil

        if state == .connected, activeHostId == host.id, let engine {
            attachEngine(engine, controller: controller)
            return
        }

        startConnection(isReconnect: false)
    }

    func disconnect(clearSession: Bool) async {
        cancelConnectTask()
        await stopEngine()
        state = .idle
        failure = nil
        reconnectBackoff.recordSuccess()

        if clearSession {
            activeHost = nil
            activeHostId = nil
            lastConnectInfo = nil
        }
    }

    func clearFailure() {
        failure = nil
    }

    private enum ReconnectReason {
        case foreground
        case networkSatisfied
        case engineDisconnected
    }

    private func requestReconnect(reason: ReconnectReason) {
        guard activeHost != nil else { return }
        guard networkPathService.isSatisfied else { return }
        guard appLifecycleService.state == .foreground else { return }
        guard connectTask == nil else { return }
        guard !isConnecting else { return }
        guard state != .connected else { return }

        startConnection(isReconnect: true)
    }

    private var isConnecting: Bool {
        switch state {
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return true
        case .idle, .disconnected, .connected, .failed:
            return false
        }
    }

    private func startConnection(isReconnect: Bool) {
        cancelConnectTask()
        let token = UUID()
        connectToken = token
        connectTask = Task { [weak self] in
            await self?.runConnectionAttempt(isReconnect: isReconnect, token: token)
        }
    }

    private func runConnectionAttempt(isReconnect: Bool, token: UUID) async {
        defer {
            if connectToken == token {
                connectTask = nil
            }
        }
        guard let host = activeHost else { return }
        let controller = self.controller
        failure = nil
        await stopEngine()
        guard connectToken == token else { return }

        if !(await applyReconnectBackoffIfNeeded(isReconnect: isReconnect, token: token)) {
            return
        }

        if isReconnect {
            state = .reconnecting
            if let connectInfo = lastConnectInfo {
                let resumed = await attemptEngineStart(
                    connectInfo: connectInfo,
                    controller: controller,
                    waitForConnection: true,
                    token: token
                )
                if resumed { return }
                await stopEngine()
            }
        }

        state = .bootstrappingSSH
        do {
            let privateKey = try keyStore.loadPrivateKeyData(keyRefId: host.keyRefId)
            let metadata = try keyStore.metadata(keyRefId: host.keyRefId)
            let requiresPassphrase = metadata?.requiresPassphrase == true
            let passphrase = await resolvePassphraseIfNeeded(
                metadata: metadata,
                host: host,
                token: token
            )
            guard connectToken == token else { return }
            if requiresPassphrase && passphrase == nil {
                return
            }
            let connectInfo = try await moshBootstrapper.bootstrap(
                host: host,
                privateKey: privateKey,
                passphrase: passphrase,
                hostKeyPrompter: hostKeyPrompter
            )
            guard connectToken == token else { return }
            lastConnectInfo = connectInfo
            state = .connectingUDP
            _ = await attemptEngineStart(
                connectInfo: connectInfo,
                controller: controller,
                waitForConnection: true,
                token: token
            )
        } catch {
            if connectToken != token { return }
            handleConnectionFailure(error)
        }
    }

    private func attemptEngineStart(
        connectInfo: MoshConnectInfo,
        controller: TerminalSessionController?,
        waitForConnection: Bool,
        token: UUID
    ) async -> Bool {
        guard connectToken == token else { return false }
        let engine = moshEngineFactory()
        self.engine = engine
        attachEngine(engine, controller: controller)

        let size = controller?.currentSize ?? TerminalSize(cols: 80, rows: 24)
        state = .connectingUDP
        do {
            try await engine.start(connectInfo: connectInfo, initialTerminalSize: size)
        } catch {
            if connectToken != token { return false }
            handleConnectionFailure(error)
            return false
        }

        guard waitForConnection else { return true }
        let connected = await waitForConnected(timeoutNanoseconds: connectionTimeoutNanoseconds, token: token)
        if !connected {
            if connectToken == token {
                handleConnectionFailure(ConnectionFailureReason.udpUnreachable)
            }
            await stopEngine()
            return false
        }
        return true
    }

    private func waitForConnected(timeoutNanoseconds: UInt64, token: UUID) async -> Bool {
        if state == .connected { return true }
        return await withCheckedContinuation { continuation in
            let waiterToken = UUID()
            connectWaiterToken = waiterToken
            connectWaiter = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard connectToken == token else { return }
                guard connectWaiterToken == waiterToken else { return }
                connectWaiterToken = nil
                connectWaiter = nil
                continuation.resume(returning: false)
            }
        }
    }

    private func attachEngine(_ engine: MoshEngine, controller: TerminalSessionController?) {
        engine.onOutput = { [weak self, weak controller, weak engine] data in
            Task { @MainActor in
                guard let self, let controller, self.engine === engine else { return }
                controller.feedOutput(data)
            }
        }

        engine.onRemoteResize = { [weak self, weak controller, weak engine] size in
            Task { @MainActor in
                guard let self, let controller, self.engine === engine else { return }
                controller.applyRemoteResize(cols: size.cols, rows: size.rows)
            }
        }

        engine.onStateChange = { [weak self, weak engine] engineState in
            Task { @MainActor in
                guard let self, self.engine === engine else { return }
                self.handleEngineState(engineState)
            }
        }

        if let controller {
            attachController(controller)
        }
    }

    private func attachController(_ controller: TerminalSessionController) {
        controller.onInput = { [weak self] data in
            Task { await self?.engine?.sendInput(data) }
        }
        controller.onSizeChange = { [weak self] size in
            Task { await self?.engine?.updateTerminalSize(cols: size.cols, rows: size.rows) }
        }
    }

    private func handleEngineState(_ engineState: MoshEngineState) {
        switch engineState {
        case .idle:
            state = .idle
        case .starting:
            state = .connectingUDP
        case .connected:
            state = .connected
            failure = nil
            reconnectBackoff.recordSuccess()
            resumeConnectWaiter(connected: true)
            recordLastConnected()
        case .disconnected:
            reconnectBackoff.recordFailure()
            let mappedFailure = ConnectionErrorMapper.map(
                error: ConnectionFailureReason.disconnected,
                host: activeHost,
                networkSatisfied: networkPathService.isSatisfied
            )
            state = .failed(message: mappedFailure.title)
            failure = mappedFailure
            resumeConnectWaiter(connected: false)
            requestReconnect(reason: .engineDisconnected)
        case .failed(let error):
            reconnectBackoff.recordFailure()
            let mappedFailure = ConnectionErrorMapper.map(
                error: error,
                host: activeHost,
                networkSatisfied: networkPathService.isSatisfied
            )
            state = .failed(message: mappedFailure.title)
            failure = mappedFailure
            resumeConnectWaiter(connected: false)
            requestReconnect(reason: .engineDisconnected)
        }
    }

    private func resumeConnectWaiter(connected: Bool) {
        guard let continuation = connectWaiter else { return }
        connectWaiter = nil
        connectWaiterToken = nil
        continuation.resume(returning: connected)
    }

    private func handleConnectionFailure(_ error: Error) {
        reconnectBackoff.recordFailure()
        let mappedFailure = ConnectionErrorMapper.map(
            error: error,
            host: activeHost,
            networkSatisfied: networkPathService.isSatisfied
        )
        state = .failed(message: mappedFailure.title)
        failure = mappedFailure
    }

    private func resolvePassphraseIfNeeded(
        metadata: StoredPrivateKeyMetadata?,
        host: HostProfile,
        token: UUID
    ) async -> String? {
        guard let metadata, metadata.requiresPassphrase else {
            return nil
        }
        let context = SSHKeyPassphraseContext(
            keyLabel: metadata.label,
            hostDisplayName: host.resolvedDisplayName,
            hostname: host.hostname,
            username: host.username
        )
        let passphrase = await passphrasePrompter.promptPassphrase(context: context)
        guard connectToken == token else { return nil }
        guard let passphrase else {
            state = .idle
            failure = nil
            return nil
        }
        return passphrase
    }

    private func recordLastConnected() {
        guard var host = activeHost else { return }
        host.lastConnectedAt = Date()
        activeHost = host
        do {
            try hostRepository.upsert(host)
        } catch {
            return
        }
    }

    private func cancelConnectTask() {
        connectTask?.cancel()
        connectTask = nil
        connectToken = UUID()
        resumeConnectWaiter(connected: false)
    }

    private func stopEngine() async {
        guard let engine else { return }
        engine.onOutput = nil
        engine.onRemoteResize = nil
        engine.onStateChange = nil
        self.engine = nil
        await engine.stop()
    }

    private func handleBackground() async {
        cancelConnectTask()
        await stopEngine()
        state = .disconnected
        failure = nil
        reconnectBackoff.recordSuccess()
    }

    private func applyReconnectBackoffIfNeeded(isReconnect: Bool, token: UUID) async -> Bool {
        guard isReconnect else { return true }
        let delaySeconds = reconnectBackoff.nextDelay()
        guard delaySeconds > 0 else { return true }
        let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
        do {
            try await sleep(nanoseconds)
        } catch {
            return false
        }
        return connectToken == token
    }
}

extension ConnectionManager.State {
    var statusText: String {
        switch self {
        case .idle:
            return "Idle"
        case .disconnected:
            return "Disconnected"
        case .bootstrappingSSH:
            return "Starting SSH"
        case .connectingUDP:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Disconnected"
        }
    }

    var shortStatusText: String {
        switch self {
        case .idle:
            return "Idle"
        case .disconnected:
            return "Disconnected"
        case .bootstrappingSSH:
            return "SSH"
        case .connectingUDP:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Disconnected"
        }
    }
}
