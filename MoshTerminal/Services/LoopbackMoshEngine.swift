import Foundation

final class LoopbackMoshEngine: MoshEngine, MoshEngineDebugProviding, @unchecked Sendable {
    var onOutput: (@Sendable (Data) -> Void)?
    var onRemoteResize: (@Sendable (TerminalSize) -> Void)?
    var onStateChange: (@Sendable (MoshEngineState) -> Void)?
    private var started = false

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws {
        guard !started else { return }
        started = true
        onStateChange?(.starting)
        onStateChange?(.connected)
        let banner = "Loopback engine active. Input echoes locally.\n"
        onOutput?(Data(banner.utf8))
    }

    func sendInput(_ bytes: Data) async {
        onOutput?(bytes)
    }

    func updateTerminalSize(cols: Int, rows: Int) async {}

    func stop() async {
        onStateChange?(.idle)
    }

    func debugSnapshot() async -> MoshEngineDebugSnapshot {
        MoshEngineDebugSnapshot(
            lastHeardAgeMillis: nil,
            sendIntervalMillis: nil,
            rtoMillis: nil,
            localPort: nil,
            consecutiveUnreachableSends: nil
        )
    }
}
