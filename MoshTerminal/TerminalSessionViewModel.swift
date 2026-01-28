import Combine
import Foundation

@MainActor
final class TerminalSessionViewModel: ObservableObject {
    struct HostKeyPromptState: Identifiable {
        let id = UUID()
        let hostKey: SSHHostKey
    }

    struct PassphrasePromptState: Identifiable {
        let id = UUID()
        let context: SSHKeyPassphraseContext
    }

    @Published var failure: ConnectionFailure?
    @Published var hostKeyPrompt: HostKeyPromptState?
    @Published var passphrasePrompt: PassphrasePromptState?

    private let host: HostProfile
    private let connectionManager: ConnectionManager
    private weak var controller: TerminalSessionController?
    private var hostKeyContinuation: CheckedContinuation<Bool, Never>?
    private var passphraseContinuation: CheckedContinuation<String?, Never>?
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init(host: HostProfile, dependencies: TerminalSessionDependencies, controller: TerminalSessionController) {
        self.host = host
        self.connectionManager = dependencies.connectionManager
        self.controller = controller
        connectionManager.$failure
            .sink { [weak self] message in
                self?.failure = message
            }
            .store(in: &cancellables)
    }

    func start(autoConnect: Bool) {
        guard autoConnect else { return }
        guard !hasStarted else { return }
        hasStarted = true
        connect()
    }

    func stop() {
        Task {
            await connectionManager.disconnect(clearSession: true)
        }
        if let continuation = hostKeyContinuation {
            hostKeyContinuation = nil
            continuation.resume(returning: false)
        }
        if let continuation = passphraseContinuation {
            passphraseContinuation = nil
            continuation.resume(returning: nil)
        }
    }

    func respondToHostKeyPrompt(shouldTrust: Bool) {
        guard let continuation = hostKeyContinuation else { return }
        hostKeyContinuation = nil
        hostKeyPrompt = nil
        continuation.resume(returning: shouldTrust)
    }

    func respondToPassphrasePrompt(passphrase: String?) {
        guard let continuation = passphraseContinuation else { return }
        passphraseContinuation = nil
        passphrasePrompt = nil
        continuation.resume(returning: passphrase)
    }

    func dismissFailure() {
        failure = nil
        connectionManager.clearFailure()
    }

    func retry() {
        dismissFailure()
        connect()
    }

    private func connect() {
        let prompter = SSHHostKeyPrompt { [weak self] hostKey in
            guard let self else { return false }
            return await self.promptForHostKey(hostKey)
        }
        let passphrasePrompter = SSHKeyPassphrasePrompt { [weak self] context in
            guard let self else { return nil }
            return await self.promptForPassphrase(context)
        }
        if let controller {
            connectionManager.connect(
                host: host,
                controller: controller,
                hostKeyPrompter: prompter,
                passphrasePrompter: passphrasePrompter
            )
        }
    }

    private func promptForHostKey(_ hostKey: SSHHostKey) async -> Bool {
        if let continuation = hostKeyContinuation {
            continuation.resume(returning: false)
        }
        return await withCheckedContinuation { continuation in
            hostKeyContinuation = continuation
            hostKeyPrompt = HostKeyPromptState(hostKey: hostKey)
        }
    }

    private func promptForPassphrase(_ context: SSHKeyPassphraseContext) async -> String? {
        if let continuation = passphraseContinuation {
            continuation.resume(returning: nil)
        }
        return await withCheckedContinuation { continuation in
            passphraseContinuation = continuation
            passphrasePrompt = PassphrasePromptState(context: context)
        }
    }
}
