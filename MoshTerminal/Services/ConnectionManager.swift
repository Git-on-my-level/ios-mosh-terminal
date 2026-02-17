import Combine
import Foundation
import MoshClientCore
import Prediction
#if DEBUG
import os
#endif

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

    @Published private(set) var state: State = .idle {
        didSet {
#if DEBUG
            logStateTransition(from: oldValue.debugName, to: state.debugName)
#endif
        }
    }
    @Published private(set) var activeHostId: UUID?
    @Published private(set) var failure: ConnectionFailure?
    @Published private(set) var statesByHostId: [UUID: State] = [:]
    @Published private(set) var failuresByHostId: [UUID: ConnectionFailure] = [:]
    @Published private(set) var persistenceOutcome: PersistenceOutcome?
    @Published private(set) var persistenceOutcomesByHostId: [UUID: PersistenceOutcome] = [:]

    private let keyStore: PrivateKeyStoring
    private let hostRepository: HostPersisting
    private let moshBootstrapper: MoshBootstrapping
    private let moshEngineFactory: MoshEngineFactory
    private let appLifecycleService: AppLifecycleProviding
    private let networkPathService: NetworkPathProviding
    private let connectionTimeoutNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let reconnectBackoffPolicy: ReconnectBackoffPolicy
    private let reconnectRandomUnit: () -> Double

    private var sessions: [UUID: SessionContext] = [:]
    private var hostsRequiringManagedSessionReset: Set<UUID> = []

    private var cancellables: Set<AnyCancellable> = []
#if DEBUG
    private var debugLogger: DebugLogProviding?
#endif

    private final class SessionContext {
        var host: HostProfile
        var hostKeyPrompter: SSHHostKeyPrompting = SSHHostKeyPrompt.denyAll
        var passphrasePrompter: SSHKeyPassphrasePrompting = SSHKeyPassphrasePrompt.denyAll
        var controller: TerminalSessionController?
        var engine: MoshEngine?
        var lastConnectInfo: MoshConnectInfo?
        var reconnectOnLifecycle = false

        var connectTask: Task<Void, Never>?
        var connectToken = UUID()

        var connectWaiterToken: UUID?
        var connectWaiter: CheckedContinuation<Bool, Never>?

        var reconnectBackoff: ReconnectBackoffState
        var autoReconnectAllowed = true

        init(
            host: HostProfile,
            reconnectBackoffPolicy: ReconnectBackoffPolicy,
            reconnectRandomUnit: @escaping () -> Double
        ) {
            self.host = host
            self.reconnectBackoff = ReconnectBackoffState(
                policy: reconnectBackoffPolicy,
                randomUnit: reconnectRandomUnit
            )
        }
    }

    struct DebugSnapshot: Sendable, Equatable {
        let lastHeardAgeMillis: UInt64?
        let sendIntervalMillis: UInt64?
        let rtoMillis: UInt64?
        let localPort: UInt16?
        let consecutiveUnreachableSends: Int?
        let predictionNetwork: PredictionNetworkSnapshot?
    }

    init(
        keyStore: PrivateKeyStoring,
        hostRepository: HostPersisting,
        moshBootstrapper: MoshBootstrapping,
        moshEngineFactory: @escaping MoshEngineFactory,
        appLifecycleService: AppLifecycleProviding,
        networkPathService: NetworkPathProviding,
        connectionTimeoutNanoseconds: UInt64 = 12_000_000_000,
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
        self.reconnectBackoffPolicy = reconnectBackoffPolicy
        self.reconnectRandomUnit = reconnectRandomUnit
        self.sleep = sleep

#if DEBUG
        self.debugLogger = DebugLogger.shared
#endif

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
        let session = session(for: host)
        session.autoReconnectAllowed = true
        session.controller = controller
        session.hostKeyPrompter = hostKeyPrompter
        session.passphrasePrompter = passphrasePrompter

        activeHostId = host.id
        syncActivePublishedState()
        setFailure(nil, hostId: host.id)
        initializePersistenceOutcomeForHostConfiguration(host)

        if state(for: host.id) == .connected, let engine = session.engine {
            attachEngine(engine, hostId: host.id, controller: controller)
            return
        }

        startConnection(hostId: host.id, isReconnect: false)
    }

    func disconnect(clearSession: Bool, resetManagedSession: Bool = false) async {
        guard let activeHostId else {
            state = .idle
            failure = nil
            return
        }
        await disconnect(hostId: activeHostId, clearSession: clearSession, resetManagedSession: resetManagedSession)
    }

    func disconnect(hostId: UUID, clearSession: Bool, resetManagedSession: Bool = false) async {
        guard let session = sessions[hostId] else {
            if clearSession {
                statesByHostId[hostId] = nil
                failuresByHostId[hostId] = nil
                persistenceOutcomesByHostId[hostId] = nil
                hostsRequiringManagedSessionReset.remove(hostId)
                if activeHostId == hostId {
                    activeHostId = nil
                    syncActivePublishedState()
                }
            }
            return
        }

        if resetManagedSession && session.host.sessionPersistenceMode == .managedTmux {
            hostsRequiringManagedSessionReset.insert(hostId)
        } else if clearSession {
            hostsRequiringManagedSessionReset.remove(hostId)
        }

        cancelConnectTask(hostId: hostId)
        await stopEngine(hostId: hostId)
        setState(.idle, hostId: hostId)
        setFailure(nil, hostId: hostId)
        session.reconnectBackoff.recordSuccess()
        session.autoReconnectAllowed = false
        session.reconnectOnLifecycle = false

        if clearSession {
            session.controller = nil
            session.lastConnectInfo = nil
            sessions[hostId] = nil
            statesByHostId[hostId] = nil
            failuresByHostId[hostId] = nil
            persistenceOutcomesByHostId[hostId] = nil

            if activeHostId == hostId {
                activeHostId = nil
            }
            syncActivePublishedState()
        }
    }

    func controller(for host: HostProfile) -> TerminalSessionController {
        let session = session(for: host)
        if let controller = session.controller {
            return controller
        }
        let controller = TerminalSessionController()
        session.controller = controller
        return controller
    }

    func state(for hostId: UUID) -> State {
        statesByHostId[hostId] ?? .idle
    }

    func failure(for hostId: UUID) -> ConnectionFailure? {
        failuresByHostId[hostId]
    }

    func persistenceOutcome(for hostId: UUID) -> PersistenceOutcome? {
        persistenceOutcomesByHostId[hostId]
    }

    func setTmuxSetupConsent(hostId: UUID, consent: TmuxSetupConsent) async {
        guard var host = sessions[hostId]?.host else { return }
        guard host.tmuxSetupConsent != consent else { return }
        host.tmuxSetupConsent = consent
        sessions[hostId]?.host = host

        if consent == .declined,
           case .fallbackPlainShell(reason: .tmuxMissingConsentRequired(let installCommand)) = persistenceOutcomesByHostId[hostId] {
            setPersistenceOutcome(
                .fallbackPlainShell(reason: .tmuxMissingConsentDeclined(installCommand: installCommand)),
                hostId: hostId
            )
        }

        do {
            try await hostRepository.upsert(host)
        } catch {
            return
        }
    }

    func retryPersistenceSetup(hostId: UUID) {
        guard let session = sessions[hostId] else { return }
        guard session.host.sessionPersistenceMode == .managedTmux else { return }
        guard networkPathService.isSatisfied else { return }
        guard appLifecycleService.state == .foreground else { return }
        cancelConnectTask(hostId: hostId)
        startConnection(hostId: hostId, isReconnect: false)
    }

    func clearFailure(hostId: UUID? = nil) {
        if let hostId {
            setFailure(nil, hostId: hostId)
            return
        }
        if let activeHostId {
            setFailure(nil, hostId: activeHostId)
        } else {
            failure = nil
        }
    }

    func debugSnapshot() async -> DebugSnapshot? {
        guard let activeHostId else { return nil }
        return await debugSnapshot(for: activeHostId)
    }

    func debugSnapshot(for hostId: UUID) async -> DebugSnapshot? {
        guard let engine = sessions[hostId]?.engine as? MoshEngineDebugProviding else { return nil }
        let snapshot = await engine.debugSnapshot()
        let predictionNetwork = (engine as? PredictionNetworkSnapshotProviding)?.predictionNetworkSnapshot()
        return DebugSnapshot(
            lastHeardAgeMillis: snapshot.lastHeardAgeMillis,
            sendIntervalMillis: snapshot.sendIntervalMillis,
            rtoMillis: snapshot.rtoMillis,
            localPort: snapshot.localPort,
            consecutiveUnreachableSends: snapshot.consecutiveUnreachableSends,
            predictionNetwork: predictionNetwork
        )
    }

    private enum ReconnectReason {
        case foreground
        case networkSatisfied
        case engineDisconnected
    }

    private func requestReconnect(reason: ReconnectReason) {
        for hostId in sessions.keys {
            requestReconnect(hostId: hostId, reason: reason)
        }
    }

    private func requestReconnect(hostId: UUID, reason: ReconnectReason) {
        guard let session = sessions[hostId] else { return }
        if reason == .foreground || reason == .networkSatisfied {
            guard session.reconnectOnLifecycle else { return }
        }
        guard session.lastConnectInfo != nil || state(for: hostId) != .idle else { return }
        guard networkPathService.isSatisfied else { return }
        guard appLifecycleService.state == .foreground else { return }
        guard session.connectTask == nil else { return }
        guard !isConnecting(state(for: hostId)) else { return }
        guard state(for: hostId) != .connected else { return }
        guard session.autoReconnectAllowed else { return }

        let reasonString: String
        switch reason {
        case .foreground:
            reasonString = "foreground"
        case .networkSatisfied:
            reasonString = "networkSatisfied"
        case .engineDisconnected:
            reasonString = "engineDisconnected"
        }
#if DEBUG
        logReconnectRequest(reason: reasonString)
#endif
        startConnection(hostId: hostId, isReconnect: true)
    }

    private func isConnecting(_ state: State) -> Bool {
        switch state {
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return true
        case .idle, .disconnected, .connected, .failed:
            return false
        }
    }

    private func session(for host: HostProfile) -> SessionContext {
        if let existing = sessions[host.id] {
            existing.host = host
            initializePersistenceOutcomeForHostConfiguration(host)
            return existing
        }
        let created = SessionContext(
            host: host,
            reconnectBackoffPolicy: reconnectBackoffPolicy,
            reconnectRandomUnit: reconnectRandomUnit
        )
        sessions[host.id] = created
        initializePersistenceOutcomeForHostConfiguration(host)
        return created
    }

    private func startConnection(hostId: UUID, isReconnect: Bool) {
        guard let session = sessions[hostId] else { return }
        cancelConnectTask(hostId: hostId)
        let token = UUID()
        session.connectToken = token
#if DEBUG
        logStartAttempt(isReconnect: isReconnect, hostId: hostId.uuidString)
#endif
        session.connectTask = Task { [weak self] in
            await self?.runConnectionAttempt(hostId: hostId, isReconnect: isReconnect, token: token)
        }
    }

    private func runConnectionAttempt(hostId: UUID, isReconnect: Bool, token: UUID) async {
        defer {
            if let session = sessions[hostId], session.connectToken == token {
                session.connectTask = nil
            }
        }

        guard let session = sessions[hostId] else { return }
        let host = session.host
        let controller = session.controller

        setFailure(nil, hostId: hostId)
        await stopEngine(hostId: hostId)
        guard session.connectToken == token else { return }

        if !(await applyReconnectBackoffIfNeeded(hostId: hostId, isReconnect: isReconnect, token: token)) {
            return
        }

        if isReconnect {
            setState(.reconnecting, hostId: hostId)
            if let connectInfo = session.lastConnectInfo {
                let resumed = await attemptEngineStart(
                    hostId: hostId,
                    connectInfo: connectInfo,
                    controller: controller,
                    waitForConnection: true,
                    token: token
                )
                if resumed { return }
                await stopEngine(hostId: hostId)
            }
        }

        setState(.bootstrappingSSH, hostId: hostId)
        do {
            let privateKey = try keyStore.loadPrivateKeyData(keyRefId: host.keyRefId)
            let metadata = try keyStore.metadata(keyRefId: host.keyRefId)
            let requiresPassphrase = metadata?.requiresPassphrase == true
            let passphrase = await resolvePassphraseIfNeeded(
                hostId: hostId,
                metadata: metadata,
                host: host,
                token: token
            )
            guard session.connectToken == token else { return }
            if requiresPassphrase && passphrase == nil {
                return
            }
            let shouldResetManagedSession = hostsRequiringManagedSessionReset.contains(hostId)
            let bootstrapResult = try await moshBootstrapper.bootstrap(
                host: host,
                privateKey: privateKey,
                passphrase: passphrase,
                hostKeyPrompter: session.hostKeyPrompter,
                resetManagedSession: shouldResetManagedSession
            )
#if DEBUG
            logSSHBootstrap(success: true, errorDescription: nil)
#endif
            guard session.connectToken == token else { return }
            session.lastConnectInfo = bootstrapResult.connectInfo
            if bootstrapResult.persistenceOutcome == .managedTmuxActive {
                hostsRequiringManagedSessionReset.remove(hostId)
            }
            setPersistenceOutcome(bootstrapResult.persistenceOutcome, hostId: hostId)
            setState(.connectingUDP, hostId: hostId)
            _ = await attemptEngineStart(
                hostId: hostId,
                connectInfo: bootstrapResult.connectInfo,
                controller: controller,
                waitForConnection: true,
                token: token
            )
        } catch {
            if session.connectToken != token { return }
#if DEBUG
            logSSHBootstrap(success: false, errorDescription: error.localizedDescription)
#endif
            handleConnectionFailure(error, hostId: hostId)
        }
    }

    private func attemptEngineStart(
        hostId: UUID,
        connectInfo: MoshConnectInfo,
        controller: TerminalSessionController?,
        waitForConnection: Bool,
        token: UUID
    ) async -> Bool {
        guard let session = sessions[hostId], session.connectToken == token else { return false }
        let engine = moshEngineFactory()
        session.engine = engine
        attachEngine(engine, hostId: hostId, controller: controller)

        let size = controller?.currentSize ?? TerminalSize(cols: 80, rows: 24)
        setState(.connectingUDP, hostId: hostId)
        do {
            try await engine.start(connectInfo: connectInfo, initialTerminalSize: size)
#if DEBUG
            logUDPConnect(success: true, timeoutMillis: nil)
#endif
        } catch {
            guard let session = sessions[hostId], session.connectToken == token else { return false }
#if DEBUG
            logUDPConnect(success: false, timeoutMillis: nil)
#endif
            handleConnectionFailure(error, hostId: hostId)
            return false
        }

        guard waitForConnection else { return true }
        let connected = await waitForConnected(hostId: hostId, timeoutNanoseconds: connectionTimeoutNanoseconds, token: token)
        if !connected {
            if let session = sessions[hostId], session.connectToken == token, state(for: hostId) == .connectingUDP {
#if DEBUG
                logUDPConnect(success: false, timeoutMillis: connectionTimeoutNanoseconds / 1_000_000)
#endif
                handleConnectionFailure(ConnectionFailureReason.udpTimeout, hostId: hostId)
            }
            await stopEngine(hostId: hostId)
            return false
        }
        return true
    }

    private func waitForConnected(hostId: UUID, timeoutNanoseconds: UInt64, token: UUID) async -> Bool {
        if state(for: hostId) == .connected { return true }
        return await withCheckedContinuation { continuation in
            guard let session = sessions[hostId] else {
                continuation.resume(returning: false)
                return
            }
            let waiterToken = UUID()
            session.connectWaiterToken = waiterToken
            session.connectWaiter = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard let session = self.sessions[hostId], session.connectToken == token else { return }
                guard session.connectWaiterToken == waiterToken else { return }
                session.connectWaiterToken = nil
                session.connectWaiter = nil
                continuation.resume(returning: false)
            }
        }
    }

    private func attachEngine(_ engine: MoshEngine, hostId: UUID, controller: TerminalSessionController?) {
#if DEBUG
        logEngineAttached()
#endif
        engine.onOutput = { [weak self, weak controller, weak engine] data in
            Task { @MainActor in
                guard let self, let controller, let engine else { return }
                guard self.sessions[hostId]?.engine === engine else { return }
                controller.feedOutput(data)
            }
        }

        engine.onRemoteResize = { [weak self, weak controller, weak engine] size in
            Task { @MainActor in
                guard let self, let controller, let engine else { return }
                guard self.sessions[hostId]?.engine === engine else { return }
                controller.applyRemoteResize(cols: size.cols, rows: size.rows)
            }
        }

        engine.onStateChange = { [weak self, weak engine] engineState in
            Task { @MainActor in
                guard let self, let engine else { return }
                guard self.sessions[hostId]?.engine === engine else { return }
                self.handleEngineState(engineState, hostId: hostId)
            }
        }

        if let controller {
            attachController(controller, hostId: hostId)
        }
    }

    private func attachController(_ controller: TerminalSessionController, hostId: UUID) {
        controller.onInput = { [weak self] data in
            Task {
                guard let self else { return }
                await self.sessions[hostId]?.engine?.sendInput(data)
            }
        }
        controller.onSizeChange = { [weak self] size in
            Task {
                guard let self else { return }
                await self.sessions[hostId]?.engine?.updateTerminalSize(cols: size.cols, rows: size.rows)
            }
        }
        let engine = sessions[hostId]?.engine
        controller.attachPredictionNetworkProvider(engine as? PredictionNetworkSnapshotProviding)
        if let notifier = engine as? PredictionEchoAckNotifying {
            notifier.onEchoAck = { [weak self, weak controller, weak notifier] _ in
                Task { @MainActor in
                    guard let self, let controller, let notifier else { return }
                    guard
                        let currentEngine = self.sessions[hostId]?.engine,
                        (currentEngine as AnyObject) === (notifier as AnyObject)
                    else { return }
                    controller.handleEchoAckUpdated()
                }
            }
        }
    }

    private func handleEngineState(_ engineState: MoshEngineState, hostId: UUID) {
        switch engineState {
        case .idle:
            setState(.idle, hostId: hostId)
        case .starting:
            setState(.connectingUDP, hostId: hostId)
        case .connected:
            setState(.connected, hostId: hostId)
            setFailure(nil, hostId: hostId)
            sessions[hostId]?.reconnectBackoff.recordSuccess()
            sessions[hostId]?.reconnectOnLifecycle = true
            resumeConnectWaiter(hostId: hostId, connected: true)
            Task { @MainActor [weak self] in
                await self?.recordLastConnected(hostId: hostId)
            }
        case .disconnected:
            sessions[hostId]?.reconnectBackoff.recordFailure()
            let mappedFailure = ConnectionErrorMapper.map(
                error: ConnectionFailureReason.disconnected,
                host: sessions[hostId]?.host,
                networkSatisfied: networkPathService.isSatisfied
            )
            setState(.failed(message: mappedFailure.title), hostId: hostId)
            setFailure(mappedFailure, hostId: hostId)
            sessions[hostId]?.autoReconnectAllowed = mappedFailure.allowsRetry
            sessions[hostId]?.reconnectOnLifecycle = false
#if DEBUG
            logFailure(title: mappedFailure.title, errorDescription: mappedFailure.message ?? "Disconnected")
#endif
            resumeConnectWaiter(hostId: hostId, connected: false)
            if sessions[hostId]?.autoReconnectAllowed == true {
                requestReconnect(hostId: hostId, reason: .engineDisconnected)
            }
        case .failed(let error):
            sessions[hostId]?.reconnectBackoff.recordFailure()
            let mappedFailure = ConnectionErrorMapper.map(
                error: error,
                host: sessions[hostId]?.host,
                networkSatisfied: networkPathService.isSatisfied
            )
            setState(.failed(message: mappedFailure.title), hostId: hostId)
            setFailure(mappedFailure, hostId: hostId)
            sessions[hostId]?.autoReconnectAllowed = mappedFailure.allowsRetry
            sessions[hostId]?.reconnectOnLifecycle = false
#if DEBUG
            logFailure(title: mappedFailure.title, errorDescription: mappedFailure.message ?? error.localizedDescription)
#endif
            resumeConnectWaiter(hostId: hostId, connected: false)
            if sessions[hostId]?.autoReconnectAllowed == true {
                requestReconnect(hostId: hostId, reason: .engineDisconnected)
            }
        }
    }

    private func resumeConnectWaiter(hostId: UUID, connected: Bool) {
        guard let continuation = sessions[hostId]?.connectWaiter else { return }
        sessions[hostId]?.connectWaiter = nil
        sessions[hostId]?.connectWaiterToken = nil
        continuation.resume(returning: connected)
    }

    private func handleConnectionFailure(_ error: Error, hostId: UUID) {
        sessions[hostId]?.reconnectBackoff.recordFailure()
        let mappedFailure = ConnectionErrorMapper.map(
            error: error,
            host: sessions[hostId]?.host,
            networkSatisfied: networkPathService.isSatisfied
        )
        setState(.failed(message: mappedFailure.title), hostId: hostId)
        setFailure(mappedFailure, hostId: hostId)
        sessions[hostId]?.autoReconnectAllowed = mappedFailure.allowsRetry
#if DEBUG
        logFailure(title: mappedFailure.title, errorDescription: mappedFailure.message ?? error.localizedDescription)
#endif
    }

    private func resolvePassphraseIfNeeded(
        hostId: UUID,
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
        let passphrase = await sessions[hostId]?.passphrasePrompter.promptPassphrase(context: context)
        guard sessions[hostId]?.connectToken == token else { return nil }
        guard let passphrase else {
            setState(.idle, hostId: hostId)
            setFailure(nil, hostId: hostId)
            sessions[hostId]?.autoReconnectAllowed = false
            sessions[hostId]?.reconnectOnLifecycle = false
            return nil
        }
        return passphrase
    }

    private func recordLastConnected(hostId: UUID) async {
        guard var host = sessions[hostId]?.host else { return }
        host.lastConnectedAt = Date()
        sessions[hostId]?.host = host
        do {
            try await hostRepository.upsert(host)
        } catch {
            return
        }
    }

    private func cancelConnectTask(hostId: UUID) {
        guard let session = sessions[hostId] else { return }
        session.connectTask?.cancel()
        session.connectTask = nil
        session.connectToken = UUID()
        resumeConnectWaiter(hostId: hostId, connected: false)
    }

    private func stopEngine(hostId: UUID) async {
        guard let engine = sessions[hostId]?.engine else { return }
        engine.onOutput = nil
        engine.onRemoteResize = nil
        engine.onStateChange = nil
#if DEBUG
        logEngineDetached()
#endif
        sessions[hostId]?.engine = nil
        await engine.stop()
    }

    private func handleBackground() async {
        let hostIds = Array(sessions.keys)
        for hostId in hostIds {
            let stateAtBackground = state(for: hostId)
            let hasResumableSession = sessions[hostId]?.lastConnectInfo != nil
            let shouldMarkDisconnected = stateAtBackground == .connected || hasResumableSession

            sessions[hostId]?.reconnectOnLifecycle = stateAtBackground == .connected
            cancelConnectTask(hostId: hostId)
            await stopEngine(hostId: hostId)
            setState(shouldMarkDisconnected ? .disconnected : .idle, hostId: hostId)
            setFailure(nil, hostId: hostId)
            sessions[hostId]?.reconnectBackoff.recordSuccess()
        }
    }

    private func applyReconnectBackoffIfNeeded(hostId: UUID, isReconnect: Bool, token: UUID) async -> Bool {
        guard isReconnect else { return true }
        guard let session = sessions[hostId] else { return false }
        let delaySeconds = session.reconnectBackoff.nextDelay()
        guard delaySeconds > 0 else { return true }
        let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
#if DEBUG
        logBackoffApplied(delaySeconds: delaySeconds)
#endif
        do {
            try await sleep(nanoseconds)
        } catch {
            return false
        }
        return sessions[hostId]?.connectToken == token
    }

    private func setState(_ newState: State, hostId: UUID) {
        statesByHostId[hostId] = newState
        if activeHostId == hostId {
            state = newState
        }
    }

    private func setFailure(_ failure: ConnectionFailure?, hostId: UUID) {
        failuresByHostId[hostId] = failure
        if activeHostId == hostId {
            self.failure = failure
        }
    }

    private func initializePersistenceOutcomeForHostConfiguration(_ host: HostProfile) {
        switch host.sessionPersistenceMode {
        case .plainShell:
            setPersistenceOutcome(
                .fallbackPlainShell(reason: .hostPreferencePlainShell),
                hostId: host.id
            )
        case .managedTmux:
            if case .fallbackPlainShell(reason: .hostPreferencePlainShell) = persistenceOutcomesByHostId[host.id] {
                persistenceOutcomesByHostId[host.id] = nil
                if activeHostId == host.id {
                    persistenceOutcome = nil
                }
            }
        }
    }

    private func setPersistenceOutcome(_ outcome: PersistenceOutcome?, hostId: UUID) {
        persistenceOutcomesByHostId[hostId] = outcome
        if activeHostId == hostId {
            persistenceOutcome = outcome
        }
    }

    private func syncActivePublishedState() {
        guard let activeHostId else {
            state = .idle
            failure = nil
            persistenceOutcome = nil
            return
        }
        state = state(for: activeHostId)
        failure = failure(for: activeHostId)
        persistenceOutcome = persistenceOutcome(for: activeHostId)
    }
}

#if DEBUG
extension ConnectionManager {
    private func logStateTransition(from: String, to: String) {
        let event = ConnectionDebugEvent(
            kind: .stateTransition(from: from, to: to),
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logStartAttempt(isReconnect: Bool, hostId: String) {
        let event = ConnectionDebugEvent(
            kind: .startAttempt(isReconnect: isReconnect, hostId: hostId),
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logReconnectRequest(reason: String) {
        let event = ConnectionDebugEvent(
            kind: .reconnectRequest(reason: reason),
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logBackoffApplied(delaySeconds: Double) {
        let event = ConnectionDebugEvent(
            kind: .backoffApplied(delaySeconds: delaySeconds),
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logSSHBootstrap(success: Bool, errorDescription: String?) {
        let event = ConnectionDebugEvent(
            kind: .sshBootstrap(success: success, errorDescription: errorDescription),
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logUDPConnect(success: Bool, timeoutMillis: UInt64?) {
        let event = ConnectionDebugEvent(
            kind: .udpConnect(success: success, timeoutMillis: timeoutMillis),
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logEngineAttached() {
        let event = ConnectionDebugEvent(
            kind: .engineAttached,
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logEngineDetached() {
        let event = ConnectionDebugEvent(
            kind: .engineDetached,
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }

    private func logFailure(title: String, errorDescription: String) {
        let event = ConnectionDebugEvent(
            kind: .failure(title: title, errorDescription: errorDescription),
            timestamp: Clock.nowMillis()
        )
        debugLogger?.logConnectionEvent(event)
    }
}
#endif

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

    var isActive: Bool {
        switch self {
        case .bootstrappingSSH, .connectingUDP, .connected, .reconnecting:
            return true
        case .idle, .disconnected, .failed:
            return false
        }
    }
}
