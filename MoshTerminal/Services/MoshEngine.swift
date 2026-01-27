import Foundation

struct TerminalSize: Equatable, Sendable {
    let cols: Int
    let rows: Int
}

enum MoshEngineState: Sendable {
    case idle
    case starting
    case connected
    case disconnected
    case failed(MoshEngineError)
}

enum MoshEngineError: Error, LocalizedError, Equatable {
    case libraryUnavailable
    case startFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return "Mosh client engine is unavailable."
        case .startFailed(let message):
            return "Mosh client failed to start: \(message)"
        }
    }
}

protocol MoshEngine: AnyObject, Sendable {
    var onOutput: (@Sendable (Data) -> Void)? { get set }
    var onStateChange: (@Sendable (MoshEngineState) -> Void)? { get set }

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws
    func sendInput(_ bytes: Data) async
    func updateTerminalSize(cols: Int, rows: Int) async
    func stop() async
}

typealias MoshEngineFactory = @Sendable () -> MoshEngine

#if canImport(MoshClient)
struct DefaultMoshEngineFactory {
    static func make() -> MoshEngineFactory {
        { MoshClientEngine() }
    }
}
#else
struct DefaultMoshEngineFactory {
    static func make() -> MoshEngineFactory {
        { UnavailableMoshEngine() }
    }
}
#endif
