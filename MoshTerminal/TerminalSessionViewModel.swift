import Combine
import Foundation

@MainActor
final class TerminalSessionViewModel: ObservableObject {
    struct HostKeyPromptState: Identifiable {
        let id = UUID()
        let hostKey: SSHHostKey
    }

    @Published var alertMessage: String?
    @Published var hostKeyPrompt: HostKeyPromptState?

    private let host: HostProfile
    private let connectionManager: ConnectionManager
    private weak var controller: TerminalSessionController?
    private var hostKeyContinuation: CheckedContinuation<Bool, Never>?
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init(host: HostProfile, dependencies: TerminalSessionDependencies, controller: TerminalSessionController) {
        self.host = host
        self.connectionManager = dependencies.connectionManager
        self.controller = controller
        connectionManager.$lastErrorMessage
            .sink { [weak self] message in
                self?.alertMessage = message
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
    }

    func respondToHostKeyPrompt(shouldTrust: Bool) {
        guard let continuation = hostKeyContinuation else { return }
        hostKeyContinuation = nil
        hostKeyPrompt = nil
        continuation.resume(returning: shouldTrust)
    }

    func dismissAlert() {
        alertMessage = nil
        connectionManager.clearLastError()
    }

    private func connect() {
        let prompter = SSHHostKeyPrompt { [weak self] hostKey in
            guard let self else { return false }
            return await self.promptForHostKey(hostKey)
        }
        if let controller {
            connectionManager.connect(host: host, controller: controller, hostKeyPrompter: prompter)
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
}
