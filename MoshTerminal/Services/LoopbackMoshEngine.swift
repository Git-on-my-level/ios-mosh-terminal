import Foundation

final class LoopbackMoshEngine: MoshEngine, @unchecked Sendable {
    var onOutput: (@Sendable (Data) -> Void)?
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
}
