import Foundation

final class TOFUHostKeyVerifier: SSHHostKeyVerifying {
    private let repository: TrustedHostKeyRepository
    private let prompter: SSHHostKeyPrompting

    init(repository: TrustedHostKeyRepository, prompter: SSHHostKeyPrompting) {
        self.repository = repository
        self.prompter = prompter
    }

    func verify(hostname: String, port: Int, fingerprint: String) async throws {
        do {
            let existing = try await repository.keys(for: hostname, port: port)
            if existing.isEmpty {
                let shouldTrust = await prompter.promptTrust(
                    hostKey: SSHHostKey(hostname: hostname, port: port, fingerprint: fingerprint)
                )
                guard shouldTrust else {
                    throw SSHClientError.hostKeyUntrusted(fingerprint: fingerprint)
                }
                let key = TrustedHostKey(hostname: hostname, port: port, fingerprint: fingerprint)
                try await repository.upsert(key)
                return
            }

            if existing.contains(where: { $0.fingerprint == fingerprint }) {
                return
            }

            throw SSHClientError.hostKeyMismatch(
                expected: existing.map { $0.fingerprint },
                actual: fingerprint
            )
        } catch let error as SSHClientError {
            throw error
        } catch {
            throw SSHClientError.storageFailure
        }
    }
}
