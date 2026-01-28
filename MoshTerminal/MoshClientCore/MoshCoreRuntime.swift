import Foundation

struct MoshCoreConnectInfo: Equatable, Sendable {
    let host: String
    let port: UInt16
    let sessionKey: String
}

struct MoshCoreTerminalSize: Equatable, Sendable {
    let cols: Int
    let rows: Int
}

actor MoshCoreRuntime {
    enum State {
        case idle
        case running
    }

    private var state: State = .idle
    private var lastSize: MoshCoreTerminalSize?

    func start(connectInfo: MoshCoreConnectInfo, initialSize: MoshCoreTerminalSize) async {
        state = .running
        lastSize = initialSize
        _ = connectInfo
    }

    func stop() async {
        state = .idle
    }

    func sendInput(_ data: Data) async {
        _ = data
    }

    func updateTerminalSize(_ size: MoshCoreTerminalSize) async {
        lastSize = size
    }
}
