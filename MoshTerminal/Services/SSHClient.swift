import Foundation

struct SSHCommandResult: Equatable {
    let stdout: String
    let stderr: String
    let exitStatus: Int32
}

enum SSHClientError: Error, LocalizedError, Equatable {
    case notConnected
    case alreadyConnected
    case authenticationFailed
    case hostKeyUntrusted(fingerprint: String)
    case hostKeyMismatch(expected: [String], actual: String)
    case connectionFailed(message: String)
    case commandFailed(exitStatus: Int32, stderr: String)
    case cancelled
    case storageFailure
    case libraryUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "SSH session is not connected."
        case .alreadyConnected:
            return "SSH session is already connected."
        case .authenticationFailed:
            return "SSH authentication failed."
        case .hostKeyUntrusted(let fingerprint):
            return "Host key is untrusted: \(fingerprint)."
        case .hostKeyMismatch(let expected, let actual):
            let expectedList = expected.joined(separator: ", ")
            return "Host key mismatch. Expected \(expectedList), got \(actual)."
        case .connectionFailed(let message):
            return "SSH connection failed: \(message)."
        case .commandFailed(let exitStatus, let stderr):
            return "Command failed with status \(exitStatus): \(stderr)."
        case .cancelled:
            return "SSH session cancelled."
        case .storageFailure:
            return "Failed to access trusted host key storage."
        case .libraryUnavailable:
            return "SSH library is unavailable."
        }
    }
}

struct SSHHostKey: Equatable, Hashable, Sendable {
    let hostname: String
    let port: Int
    let fingerprint: String
}

protocol SSHHostKeyPrompting: Sendable {
    func promptTrust(hostKey: SSHHostKey) async -> Bool
}

struct SSHHostKeyPrompt: SSHHostKeyPrompting, Sendable {
    let handler: @Sendable (SSHHostKey) async -> Bool

    func promptTrust(hostKey: SSHHostKey) async -> Bool {
        await handler(hostKey)
    }

    static let denyAll = SSHHostKeyPrompt { _ in false }
}

protocol SSHHostKeyVerifying: Sendable {
    func verify(hostname: String, port: Int, fingerprint: String) async throws
}

typealias SSHClientFactory = (SSHHostKeyPrompting) -> SSHClient

protocol SSHClient: Sendable {
    func connect(
        host: String,
        port: Int,
        username: String,
        privateKey: Data,
        passphrase: String?
    ) async throws

    func fetchHostKeyFingerprint() async throws -> String

    func execute(command: String) async throws -> SSHCommandResult

    func disconnect() async

    func cancel() async
}

#if canImport(libssh2)
struct DefaultSSHClientFactory {
    static func make(repository: TrustedHostKeyRepository) -> SSHClientFactory {
        { prompter in
            let verifier = TOFUHostKeyVerifier(repository: repository, prompter: prompter)
            return LibSSH2Client(hostKeyVerifier: verifier)
        }
    }
}
#else
struct DefaultSSHClientFactory {
    static func make(repository: TrustedHostKeyRepository) -> SSHClientFactory {
        { prompter in
            let verifier = TOFUHostKeyVerifier(repository: repository, prompter: prompter)
            return UnavailableSSHClient(hostKeyVerifier: verifier)
        }
    }
}
#endif
