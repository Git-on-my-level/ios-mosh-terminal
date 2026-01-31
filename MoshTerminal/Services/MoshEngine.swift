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
    case udpUnreachable
    case integrityFailure

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return "Mosh client engine is unavailable."
        case .startFailed(let message):
            return "Mosh client failed to start: \(message)"
        case .udpUnreachable:
            return "UDP appears blocked or unreachable."
        case .integrityFailure:
            return "Too many invalid packets were received."
        }
    }
}

protocol MoshEngine: AnyObject, Sendable {
    var onOutput: (@Sendable (Data) -> Void)? { get set }
    var onRemoteResize: (@Sendable (TerminalSize) -> Void)? { get set }
    var onStateChange: (@Sendable (MoshEngineState) -> Void)? { get set }

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws
    func sendInput(_ bytes: Data) async
    func updateTerminalSize(cols: Int, rows: Int) async
    func stop() async
}

struct MoshEngineDebugSnapshot: Sendable, Equatable {
    let lastHeardAgeMillis: UInt64?
    let sendIntervalMillis: UInt64?
    let rtoMillis: UInt64?
    let localPort: UInt16?
    let consecutiveUnreachableSends: Int?
}

protocol MoshEngineDebugProviding: AnyObject, Sendable {
    func debugSnapshot() async -> MoshEngineDebugSnapshot
}

protocol PredictionNetworkSnapshotProviding: AnyObject, Sendable {
    func predictionNetworkSnapshot() -> PredictionNetworkSnapshot
}

protocol PredictionEchoAckNotifying: AnyObject, Sendable {
    var onEchoAck: (@Sendable (UInt64) -> Void)? { get set }
}

typealias MoshEngineFactory = @Sendable () -> MoshEngine

struct DefaultMoshEngineFactory {
    static func make() -> MoshEngineFactory {
        { NativeMoshEngine() }
    }
}
