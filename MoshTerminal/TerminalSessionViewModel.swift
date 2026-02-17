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

    struct TmuxSetupPromptState: Identifiable {
        let id = UUID()
        let installCommand: String
    }

    @Published var failure: ConnectionFailure?
    @Published var hostKeyPrompt: HostKeyPromptState?
    @Published var passphrasePrompt: PassphrasePromptState?
    @Published var tmuxSetupPrompt: TmuxSetupPromptState?
    @Published private(set) var persistenceOutcome: PersistenceOutcome?

    private let host: HostProfile
    private let connectionManager: ConnectionManager
    private weak var controller: TerminalSessionController?
    private var hostKeyContinuation: CheckedContinuation<Bool, Never>?
    private var passphraseContinuation: CheckedContinuation<String?, Never>?
    private var hasStarted = false
    private var hasHandledTmuxConsentPrompt: Bool
    private var cancellables: Set<AnyCancellable> = []

    init(host: HostProfile, dependencies: TerminalSessionDependencies, controller: TerminalSessionController) {
        self.host = host
        self.connectionManager = dependencies.connectionManager
        self.controller = controller
        self.hasHandledTmuxConsentPrompt = host.tmuxSetupConsent != .unknown
        failure = connectionManager.failure(for: host.id)
        persistenceOutcome = connectionManager.persistenceOutcome(for: host.id)
        connectionManager.$failuresByHostId
            .map { failures in
                failures[host.id]
            }
            .removeDuplicates()
            .sink { [weak self] message in
                self?.failure = message
            }
            .store(in: &cancellables)
        connectionManager.$persistenceOutcomesByHostId
            .map { outcomes in
                outcomes[host.id]
            }
            .removeDuplicates()
            .sink { [weak self] outcome in
                self?.handlePersistenceOutcome(outcome)
            }
            .store(in: &cancellables)
    }

    var persistenceWarning: PersistenceWarning? {
        ConnectionErrorMapper.mapPersistenceWarning(outcome: persistenceOutcome)
    }

    var persistenceBadgeText: String {
        switch persistenceOutcome {
        case .managedTmuxActive:
            return "Managed"
        case .fallbackPlainShell:
            return "Plain"
        case nil:
            switch host.sessionPersistenceMode {
            case .managedTmux:
                return "Managed"
            case .plainShell:
                return "Plain"
            }
        }
    }

    var persistenceBadgeIsWarning: Bool {
        guard case .fallbackPlainShell(let reason)? = persistenceOutcome else { return false }
        return reason.isWarning
    }

    func start(autoConnect: Bool) {
        guard autoConnect else { return }
        guard !hasStarted else { return }
        hasStarted = true
        connect()
    }

    func stop(resetManagedSession: Bool = false) {
        Task {
            await connectionManager.disconnect(
                hostId: host.id,
                clearSession: true,
                resetManagedSession: resetManagedSession
            )
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
        connectionManager.clearFailure(hostId: host.id)
    }

    func retry() {
        dismissFailure()
        connect()
    }

    func retryPersistenceSetup() {
        connectionManager.retryPersistenceSetup(hostId: host.id)
    }

    func respondToTmuxSetupPrompt(approveInstall: Bool) {
        tmuxSetupPrompt = nil
        hasHandledTmuxConsentPrompt = true
        if approveInstall {
            Task {
                await connectionManager.setTmuxSetupConsent(hostId: host.id, consent: .approved)
                connectionManager.retryPersistenceSetup(hostId: host.id)
            }
        } else {
            Task {
                await connectionManager.setTmuxSetupConsent(hostId: host.id, consent: .declined)
            }
        }
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

    private func handlePersistenceOutcome(_ outcome: PersistenceOutcome?) {
        persistenceOutcome = outcome
        guard !hasHandledTmuxConsentPrompt else { return }
        guard case .fallbackPlainShell(reason: .tmuxMissingConsentRequired(let installCommand))? = outcome else {
            return
        }
        hasHandledTmuxConsentPrompt = true
        tmuxSetupPrompt = TmuxSetupPromptState(installCommand: installCommand)
    }
}
