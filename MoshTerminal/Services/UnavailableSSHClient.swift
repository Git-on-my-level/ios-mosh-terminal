import Foundation

final class UnavailableSSHClient: SSHClient {
    private let hostKeyVerifier: SSHHostKeyVerifying?

    init(hostKeyVerifier: SSHHostKeyVerifying? = nil) {
        self.hostKeyVerifier = hostKeyVerifier
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        privateKey: Data,
        passphrase: String?
    ) async throws {
        _ = hostKeyVerifier
        throw SSHClientError.libraryUnavailable
    }

    func fetchHostKeyFingerprint() async throws -> String {
        throw SSHClientError.libraryUnavailable
    }

    func execute(command: String) async throws -> SSHCommandResult {
        _ = command
        throw SSHClientError.libraryUnavailable
    }

    func disconnect() async {
    }

    func cancel() async {
    }
}
