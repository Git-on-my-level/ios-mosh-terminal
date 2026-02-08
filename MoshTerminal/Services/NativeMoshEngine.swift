import Foundation

private actor NativeMoshEngineState {
    enum State {
        case idle
        case starting
        case connected
        case stopping
    }

    private var state: State = .idle

    func beginStart() -> Bool {
        guard state == .idle else { return false }
        state = .starting
        return true
    }

    func markConnected() {
        if state == .starting {
            state = .connected
        }
    }

    func beginStop() -> Bool {
        guard state != .idle else { return false }
        state = .stopping
        return true
    }

    func markIdle() {
        state = .idle
    }
}

/// `@unchecked Sendable` because runtime state is isolated to `MoshRuntime` and
/// `NativeMoshEngineState` actors; handler references are set on the main actor.
final class NativeMoshEngine: MoshEngine, MoshEngineDebugProviding, PredictionNetworkSnapshotProviding, PredictionEchoAckNotifying, @unchecked Sendable {
    var onOutput: (@Sendable (Data) -> Void)?
    var onRemoteResize: (@Sendable (TerminalSize) -> Void)?
    var onStateChange: (@Sendable (MoshEngineState) -> Void)?
    var onEchoAck: (@Sendable (UInt64) -> Void)?

    private let runtime = MoshRuntime()
    private let state = NativeMoshEngineState()

    deinit {
        let runtime = self.runtime
        Task { await runtime.stop() }
    }

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws {
        guard await state.beginStart() else { return }
        onStateChange?(.starting)

        await runtime.setHandlers(
            onOutput: { [weak self] data in
                self?.onOutput?(data)
            },
            onRemoteResize: { [weak self] size in
                self?.onRemoteResize?(size)
            },
            onEvent: { [weak self] event in
                guard let self else { return }
                switch event {
                case .connected:
                    Task { await self.state.markConnected() }
                    self.onStateChange?(.connected)
                case .disconnected:
                    Task { await self.state.markIdle() }
                    self.onStateChange?(.disconnected)
                case .failed(let error):
                    Task { await self.state.markIdle() }
                    self.onStateChange?(.failed(error))
                }
            },
            onEchoAck: { [weak self] value in
                self?.onEchoAck?(value)
            }
        )

        do {
            try await runtime.start(
                serverHost: connectInfo.serverAddress,
                udpPort: UInt16(connectInfo.udpPort),
                key: connectInfo.sessionKey,
                initialSize: initialTerminalSize
            )
        } catch {
            await state.markIdle()
            onStateChange?(.failed(.startFailed(message: error.localizedDescription)))
            throw error
        }
    }

    func sendInput(_ bytes: Data) async {
        await runtime.sendInput(bytes)
    }

    func updateTerminalSize(cols: Int, rows: Int) async {
        await runtime.resize(cols: cols, rows: rows)
    }

    func stop() async {
        guard await state.beginStop() else { return }
        await runtime.stop()
        await state.markIdle()
        onStateChange?(.idle)
    }

    func debugSnapshot() async -> MoshEngineDebugSnapshot {
        await runtime.debugSnapshot()
    }

    nonisolated func predictionNetworkSnapshot() -> PredictionNetworkSnapshot {
        runtime.predictionNetworkSnapshot()
    }
}
