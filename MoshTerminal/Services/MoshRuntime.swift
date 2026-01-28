import Foundation

actor MoshRuntime {
    enum Event: Sendable {
        case connected
        case disconnected
        case failed(message: String)
    }

    struct Configuration: Sendable {
        var mtu: Int = 1400
        var socketFactory: @Sendable (String, UInt16) throws -> DatagramSocket = { host, port in
            try RoamingDatagramSocket(host: host, port: port)
        }
        var idleTickSleepMillis: UInt64 = 250
    }

    private enum State {
        case idle
        case running
        case stopping
    }

    var onOutput: (@Sendable (Data) -> Void)?
    var onRemoteResize: (@Sendable (TerminalSize) -> Void)?
    var onEvent: (@Sendable (Event) -> Void)?

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

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func setHandlers(
        onOutput: (@Sendable (Data) -> Void)?,
        onRemoteResize: (@Sendable (TerminalSize) -> Void)?,
        onEvent: (@Sendable (Event) -> Void)?
    ) async {
        self.onOutput = onOutput
        self.onRemoteResize = onRemoteResize
        self.onEvent = onEvent
    }

    func start(serverHost: String, udpPort: UInt16, key: String, initialSize: TerminalSize) async throws {
        guard state == .idle else { return }
        state = .running
        hasEmittedConnected = false
        lastSize = initialSize

        let sessionKey = try SessionKey.decode(key)
        let ocbSession = try OCBSession(key16: sessionKey)
        let packetCodec = OCBPacketCodec(session: ocbSession)
        let framing = TransportFraming(packetCodec: packetCodec)
        let sender = TransportSender()
        sender.setConnected(true, nowMillis: Clock.nowMillis())
        sender.currentState.append(.resize(cols: initialSize.cols, rows: initialSize.rows))

        let outputHandler: (Data) -> Void = { [weak self] data in
            Task { await self?.emitOutput(data) }
        }
        let resizeHandler: (Int, Int) -> Void = { [weak self] cols, rows in
            Task { await self?.emitRemoteResize(cols: cols, rows: rows) }
        }
        let receiver = TransportReceiver(
            transportSender: sender,
            hostApplier: HostDiffApplier(
                onTerminalOutput: outputHandler,
                onResize: resizeHandler,
                onEchoAck: nil
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

    private enum StopReason {
        case user
        case remote
        case failure
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

        if reason == .remote {
            emitEvent(.disconnected)
        }
    }

    private func runReceiveLoop() async {
        guard let socket else { return }
        while !Task.isCancelled {
            do {
                let datagram = try await socket.receive()
                guard let instruction = try framing?.processInboundDatagram(datagram) else {
                    continue
                }
                try receiver?.process(instruction)
                if !hasEmittedConnected {
                    hasEmittedConnected = true
                    emitEvent(.connected)
                }
            } catch {
                if Task.isCancelled || state != .running {
                    break
                }
                emitEvent(.failed(message: error.localizedDescription))
                await stopInternal(reason: .failure)
                break
            }
        }
    }

    private func runTickLoop() async {
        while !Task.isCancelled {
            guard state == .running else { break }
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
            let instructions = sender.tick(nowMillis: Clock.nowMillis())
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
                    }
                } catch {
                    if Task.isCancelled || state != .running {
                        return
                    }
                    emitEvent(.failed(message: error.localizedDescription))
                    await stopInternal(reason: .failure)
                    return
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

    private func emitEvent(_ event: Event) {
        onEvent?(event)
    }

    private func handleRemoteDisconnect() async {
        guard state == .running else { return }
        await stopInternal(reason: .remote)
    }
}
