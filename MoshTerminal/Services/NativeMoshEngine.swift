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

final class NativeMoshEngine: MoshEngine, @unchecked Sendable {
    var onOutput: (@Sendable (Data) -> Void)?
    var onStateChange: (@Sendable (MoshEngineState) -> Void)?

    private let runtime = MoshCoreRuntime()
    private let state = NativeMoshEngineState()
    private let banner = "Native engine scaffolding active. Protocol runtime pending.\n"

    deinit {
        let runtime = self.runtime
        Task { await runtime.stop() }
    }

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws {
        guard await state.beginStart() else { return }
        onStateChange?(.starting)

        let coreInfo = MoshCoreConnectInfo(
            host: connectInfo.serverAddress,
            port: UInt16(connectInfo.udpPort),
            sessionKey: connectInfo.sessionKey
        )
        let coreSize = MoshCoreTerminalSize(
            cols: initialTerminalSize.cols,
            rows: initialTerminalSize.rows
        )

        await runtime.start(connectInfo: coreInfo, initialSize: coreSize)
        await state.markConnected()
        onStateChange?(.connected)
        onOutput?(Data(banner.utf8))
    }

    func sendInput(_ bytes: Data) async {
        await runtime.sendInput(bytes)
    }

    func updateTerminalSize(cols: Int, rows: Int) async {
        let size = MoshCoreTerminalSize(cols: cols, rows: rows)
        await runtime.updateTerminalSize(size)
    }

    func stop() async {
        guard await state.beginStop() else { return }
        await runtime.stop()
        await state.markIdle()
        onStateChange?(.idle)
    }
}
