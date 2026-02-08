import Foundation

/// `@unchecked Sendable` because it is only used on the main actor and holds
/// mutable handler references without additional synchronization.
final class UnavailableMoshEngine: MoshEngine, @unchecked Sendable {
    var onOutput: (@Sendable (Data) -> Void)?
    var onRemoteResize: (@Sendable (TerminalSize) -> Void)?
    var onStateChange: (@Sendable (MoshEngineState) -> Void)?

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws {
        onStateChange?(.failed(MoshEngineError.libraryUnavailable))
        throw MoshEngineError.libraryUnavailable
    }

    func sendInput(_ bytes: Data) async {}

    func updateTerminalSize(cols: Int, rows: Int) async {}

    func stop() async {
        onStateChange?(.idle)
    }
}
