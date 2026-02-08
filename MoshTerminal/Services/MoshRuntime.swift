import Darwin
import Foundation
import MoshClientCore
import Prediction

final class PredictionNetworkSnapshotStore: Sendable {
    private let lock = NSLock()
    private var _snapshot = PredictionNetworkSnapshot(
        lastSentStateNum: 0,
        lastAckedStateNum: 0,
        echoAck: 0,
        srttMillis: nil
    )

    func setLastSent(_ value: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        _snapshot = PredictionNetworkSnapshot(
            lastSentStateNum: value,
            lastAckedStateNum: _snapshot.lastAckedStateNum,
            echoAck: _snapshot.echoAck,
            srttMillis: _snapshot.srttMillis
        )
    }

    func setLastAcked(_ value: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        _snapshot = PredictionNetworkSnapshot(
            lastSentStateNum: _snapshot.lastSentStateNum,
            lastAckedStateNum: value,
            echoAck: _snapshot.echoAck,
            srttMillis: _snapshot.srttMillis
        )
    }

    func setEchoAck(_ value: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        _snapshot = PredictionNetworkSnapshot(
            lastSentStateNum: _snapshot.lastSentStateNum,
            lastAckedStateNum: _snapshot.lastAckedStateNum,
            echoAck: value,
            srttMillis: _snapshot.srttMillis
        )
    }

    func setSrtt(_ value: UInt64?) {
        lock.lock()
        defer { lock.unlock() }
        _snapshot = PredictionNetworkSnapshot(
            lastSentStateNum: _snapshot.lastSentStateNum,
            lastAckedStateNum: _snapshot.lastAckedStateNum,
            echoAck: _snapshot.echoAck,
            srttMillis: value
        )
    }

    func snapshot() -> PredictionNetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _snapshot
    }
}

actor MoshRuntime: PredictionNetworkSnapshotProviding {
    enum Event: Sendable {
        case connected
        case disconnected
        case failed(MoshEngineError)
    }

    struct Configuration: Sendable {
        struct LivenessPolicy: Sendable {
            /// Disconnect if we have seen no inbound UDP packets for this long.
            var inboundSilenceMillis: UInt64 = 15_000
            /// Allow extra idle time before disconnecting if no network errors are observed.
            var idleGraceMillis: UInt64 = 30_000
            /// Fail the session after this many consecutive corrupted packets.
            var corruptPacketThreshold: Int = 6
            /// Fail the session after this many consecutive UDP unreachable send errors.
            var unreachableSendThreshold: Int = 3
        }

        var mtu: Int = 1400
        var socketFactory: @Sendable (String, UInt16) throws -> DatagramSocket = { host, port in
            try RoamingDatagramSocket(host: host, port: port)
        }
        var idleTickSleepMillis: UInt64 = 250
        var keepaliveIntervalMillis: UInt64 = TransportSender.Constants.keepaliveIntervalMillis
        var livenessPolicy: LivenessPolicy = LivenessPolicy()
    }

    private enum State {
        case idle
        case running
        case stopping
    }

    var onOutput: (@Sendable (Data) -> Void)?
    var onRemoteResize: (@Sendable (TerminalSize) -> Void)?
    var onEvent: (@Sendable (Event) -> Void)?
    var onEchoAck: (@Sendable (UInt64) -> Void)?

    private let configuration: Configuration
    private var state: State = .idle
    private var socket: DatagramSocket?
    private var framing: TransportFraming?
    private var sender: TransportSender?
    private var receiver: TransportReceiver?
    private var receiveTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var hasEmittedConnected = false
    private var lastSize: TerminalSize?
    private var lastHeardMillis: UInt64?
    private var lastRoundtripSuccessMillis: UInt64?
    private var consecutiveCorruptPackets: Int = 0
    private var consecutiveUnreachableSends: Int = 0
    private nonisolated let predictionNetworkStore = PredictionNetworkSnapshotStore()
#if DEBUG
    private var debugLogger: DebugLogProviding?
#endif

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
#if DEBUG
        self.debugLogger = DebugLogger.shared
#endif
    }

    func setHandlers(
        onOutput: (@Sendable (Data) -> Void)?,
        onRemoteResize: (@Sendable (TerminalSize) -> Void)?,
        onEvent: (@Sendable (Event) -> Void)?,
        onEchoAck: (@Sendable (UInt64) -> Void)?
    ) async {
        self.onOutput = onOutput
        self.onRemoteResize = onRemoteResize
        self.onEvent = onEvent
        self.onEchoAck = onEchoAck
    }

    func start(serverHost: String, udpPort: UInt16, key: String, initialSize: TerminalSize) async throws {
        guard state == .idle else { return }
        state = .running
        hasEmittedConnected = false
        lastSize = initialSize
        lastHeardMillis = Clock.nowMillis()
        lastRoundtripSuccessMillis = nil
        consecutiveCorruptPackets = 0
        consecutiveUnreachableSends = 0

        let sessionKey = try SessionKey.decode(key)
        let ocbSession = try OCBSession(key16: sessionKey)
        let packetCodec = OCBPacketCodec(session: ocbSession)
        let framing = TransportFraming(packetCodec: packetCodec)
        let sender = TransportSender(keepaliveIntervalMillis: configuration.keepaliveIntervalMillis)
        sender.setConnected(true, nowMillis: Clock.nowMillis())
        sender.currentState.append(.resize(cols: initialSize.cols, rows: initialSize.rows))

        let outputHandler: (Data) -> Void = { [weak self] data in
            Task { await self?.emitOutput(data) }
        }
        let resizeHandler: (Int, Int) -> Void = { [weak self] cols, rows in
            Task { await self?.emitRemoteResize(cols: cols, rows: rows) }
        }
        let echoAckUpdateHandler: (UInt64) -> Void = { [predictionNetworkStore] value in
            predictionNetworkStore.setEchoAck(value)
#if DEBUG
            let event = PredictionDebugEvent(kind: .echoAckUpdate(value: value), timestamp: Clock.nowMillis())
            debugLogger?.logPredictionEvent(event)
#endif
        }
        let echoAckStandaloneHandler: (UInt64) -> Void = { [weak self] value in
            Task { await self?.emitEchoAck(value) }
        }
        let receiver = TransportReceiver(
            transportSender: sender,
            hostApplier: HostDiffApplier(
                onTerminalOutput: outputHandler,
                onResize: resizeHandler,
                onEchoAckUpdate: echoAckUpdateHandler,
                onEchoAckStandalone: echoAckStandaloneHandler
            ),
            onDisconnect: { [weak self] in
                Task { await self?.handleRemoteDisconnect() }
            }
        )

        let socket = try configuration.socketFactory(serverHost, udpPort)

        self.socket = socket
        self.framing = framing
        self.sender = sender
        self.receiver = receiver

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
        tickTask = Task { [weak self] in
            await self?.runTickLoop()
        }
    }

    func sendInput(_ data: Data) async {
        guard state == .running, !data.isEmpty else { return }
        sender?.currentState.append(.keystroke(data))
    }

    func resize(cols: Int, rows: Int) async {
        let size = TerminalSize(cols: cols, rows: rows)
        lastSize = size
        guard state == .running else { return }
        sender?.currentState.append(.resize(cols: cols, rows: rows))
    }

    func stop() async {
        await stopInternal(reason: .user)
    }

    func debugSnapshot(nowMillis: UInt64 = Clock.nowMillis()) -> MoshEngineDebugSnapshot {
        let lastHeardAge = lastHeardMillis.map { nowMillis >= $0 ? nowMillis - $0 : 0 }
        let sendInterval = sender?.debugSendIntervalMillis(nowMillis: nowMillis)
        let rto = sender?.debugRtoMillis
        let port = (socket as? DatagramSocketPortProviding)?.localPort
        let normalizedPort: UInt16? = (port == 0) ? nil : port
        return MoshEngineDebugSnapshot(
            lastHeardAgeMillis: lastHeardAge,
            sendIntervalMillis: sendInterval,
            rtoMillis: rto,
            localPort: normalizedPort,
            consecutiveUnreachableSends: consecutiveUnreachableSends
        )
    }

    nonisolated func predictionNetworkSnapshot() -> PredictionNetworkSnapshot {
        return predictionNetworkStore.snapshot()
    }

    private enum StopReason {
        case user
        case remote
        case failure
        case liveness
    }

    private func stopInternal(reason: StopReason) async {
        guard state == .running else { return }
        state = .stopping

        receiveTask?.cancel()
        tickTask?.cancel()
        receiveTask = nil
        tickTask = nil
        socket?.close()
        socket = nil
        framing = nil
        sender = nil
        receiver = nil
        state = .idle

        if reason == .remote || reason == .liveness {
#if DEBUG
            let reasonString: String
            switch reason {
            case .remote:
                reasonString = "remote"
            case .liveness:
                reasonString = "liveness timeout"
            default:
                reasonString = "unknown"
            }
            logLivenessEvent(.disconnected(reason: reasonString))
#endif
            emitEvent(.disconnected)
        }
    }

    private func runReceiveLoop() async {
        guard let socket else { return }
        while !Task.isCancelled {
            do {
                let datagram = try await socket.receive()
                let now = Clock.nowMillis()
                lastHeardMillis = now
                guard let instruction = try framing?.processInboundDatagram(datagram) else {
                    continue
                }
                let previousAck = sender?.lastAckedStateNumPublic ?? 0
                try receiver?.process(instruction, nowMillis: now)
                let currentAck = sender?.lastAckedStateNumPublic ?? previousAck
                if currentAck > previousAck {
                    lastRoundtripSuccessMillis = now
                    predictionNetworkStore.setLastAcked(currentAck)
                }
                consecutiveCorruptPackets = 0
                if !hasEmittedConnected {
                    hasEmittedConnected = true
#if DEBUG
                    logLivenessEvent(.connected)
#endif
                    emitEvent(.connected)
                }
            } catch {
                if Task.isCancelled || state != .running {
                    break
                }
                let now = Clock.nowMillis()
                if shouldCountCorrupt(error) {
                    consecutiveCorruptPackets += 1
#if DEBUG
                    logLivenessEvent(.corruptPacket(consecutiveCount: consecutiveCorruptPackets))
#endif
                    if consecutiveCorruptPackets >= configuration.livenessPolicy.corruptPacketThreshold {
#if DEBUG
                        logLivenessEvent(.failed(error: "Integrity failure"))
#endif
                        emitEvent(.failed(.integrityFailure))
                        await stopInternal(reason: .failure)
                        break
                    }
                    lastHeardMillis = now
                    continue
                }

#if DEBUG
                logLivenessEvent(.failed(error: error.localizedDescription))
#endif
                emitEvent(.failed(.startFailed(message: error.localizedDescription)))
                await stopInternal(reason: .failure)
                break
            }
        }
    }

    private func runTickLoop() async {
        while !Task.isCancelled {
            guard state == .running else { break }
            if await checkLiveness() {
                break
            }
            let now = Clock.nowMillis()
            let wait = sender?.waitTime(nowMillis: now) ?? Int.max
            let sleepMillis: UInt64
            if wait == Int.max {
                sleepMillis = configuration.idleTickSleepMillis
            } else {
                sleepMillis = UInt64(max(0, wait))
            }

            if sleepMillis > 0 {
                do {
                    try await Task.sleep(nanoseconds: sleepMillis * 1_000_000)
                } catch {
                    break
                }
            }

            guard let sender, let framing, let socket else { break }
            let tickNow = Clock.nowMillis()
            let instructions = sender.tick(nowMillis: tickNow)
            
            predictionNetworkStore.setLastSent(sender.lastSentStateNumPublic)
            if let srtt = sender.srttMillisPublic {
                predictionNetworkStore.setSrtt(srtt)
            }
            
#if DEBUG
            let snap = predictionNetworkStore.snapshot()
            let event = PredictionDebugEvent(
                kind: .networkSnapshot(
                    lastSentStateNum: snap.lastSentStateNum,
                    lastAckedStateNum: snap.lastAckedStateNum,
                    echoAck: snap.echoAck,
                    srttMillis: snap.srttMillis
                ),
                timestamp: Clock.nowMillis()
            )
            debugLogger?.logPredictionEvent(event)
#endif
            
            if instructions.isEmpty {
                continue
            }

            for instruction in instructions {
                do {
                    let datagrams = try framing.makeOutboundDatagrams(
                        instruction: instruction,
                        mtu: configuration.mtu
                    )
                    for datagram in datagrams {
                        try socket.send(datagram)
                        consecutiveUnreachableSends = 0
                    }
#if DEBUG
                    if instruction.diff.isEmpty && instruction.newNum == 0 {
                        logLivenessEvent(.keepaliveSent)
                    }
#endif
                } catch {
                    if Task.isCancelled || state != .running {
                        return
                    }
                    if let failure = handleSendError(error) {
                        emitEvent(.failed(failure))
                        await stopInternal(reason: .failure)
                        return
                    }
                }
            }
        }
    }

    private func emitOutput(_ data: Data) {
        onOutput?(data)
    }

    private func emitRemoteResize(cols: Int, rows: Int) {
        let size = TerminalSize(cols: cols, rows: rows)
        lastSize = size
        onRemoteResize?(size)
    }

    private func emitEchoAck(_ value: UInt64) {
        onEchoAck?(value)
    }

    private func emitEvent(_ event: Event) {
        onEvent?(event)
    }

    private func handleRemoteDisconnect() async {
        guard state == .running else { return }
        await stopInternal(reason: .remote)
    }

    private func checkLiveness() async -> Bool {
        guard state == .running else { return true }
        let now = Clock.nowMillis()
        if let lastHeardMillis {
            let silenceDeadline = lastHeardMillis &+ configuration.livenessPolicy.inboundSilenceMillis
            if now > silenceDeadline {
                let lastHeardAge = now &- lastHeardMillis
                let graceDeadline = silenceDeadline &+ configuration.livenessPolicy.idleGraceMillis
#if DEBUG
                logLivenessEvent(.livenessCheck(lastHeardAge: lastHeardAge, consecutiveUnreachable: consecutiveUnreachableSends))
#endif
                if consecutiveUnreachableSends > 0 || now > graceDeadline {
                    await stopInternal(reason: .liveness)
                    return true
                }
            }
        }
        return false
    }

    private func shouldCountCorrupt(_ error: Error) -> Bool {
        switch error {
        case is PacketCodecError,
             is OCBSessionError,
             is TransportFramingError,
             is FragmentError,
             is FragmentAssemblyError,
             is ZlibCodecError,
             is ProtoCodecError,
             is TransportReceiveError:
            return true
        default:
            return false
        }
    }

    private func handleSendError(_ error: Error) -> MoshEngineError? {
        if let socketError = error as? DatagramSocketError {
            if case .sendFailed(let errno) = socketError {
                if isUnreachableErrno(errno) {
                    consecutiveUnreachableSends += 1
#if DEBUG
                    logLivenessEvent(.unreachableSend(consecutiveCount: consecutiveUnreachableSends))
#endif
                    if consecutiveUnreachableSends >= configuration.livenessPolicy.unreachableSendThreshold {
                        return .udpUnreachable
                    }
                    return nil
                }
            }
        }
        return .startFailed(message: error.localizedDescription)
    }

    private func isUnreachableErrno(_ value: Int32) -> Bool {
        switch value {
        case ENETUNREACH, EHOSTUNREACH, ENETDOWN, EHOSTDOWN, EADDRNOTAVAIL:
            return true
        default:
            return false
        }
    }
}

#if DEBUG
extension MoshRuntime {
    private func logLivenessEvent(_ kind: LivenessDebugEvent.Kind) {
        let event = LivenessDebugEvent(kind: kind, timestamp: Clock.nowMillis())
        debugLogger?.logLivenessEvent(event)
    }
}
#endif
