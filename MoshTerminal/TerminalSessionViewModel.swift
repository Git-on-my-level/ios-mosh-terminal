import Foundation

@MainActor
final class TerminalSessionViewModel: ObservableObject {
    struct HostKeyPromptState: Identifiable {
        let id = UUID()
        let hostKey: SSHHostKey
    }

    @Published var alertMessage: String?
    @Published var hostKeyPrompt: HostKeyPromptState?
    @Published var connectionState: MoshEngineState = .idle

    private let host: HostProfile
    private let dependencies: TerminalSessionDependencies
    private weak var controller: TerminalSessionController?
    private var engine: MoshEngine?
    private var hostKeyContinuation: CheckedContinuation<Bool, Never>?
    private var hasStarted = false

    init(host: HostProfile, dependencies: TerminalSessionDependencies, controller: TerminalSessionController) {
        self.host = host
        self.dependencies = dependencies
        self.controller = controller
    }

    func start(autoConnect: Bool) {
        guard autoConnect else { return }
        guard !hasStarted else { return }
        hasStarted = true
        Task {
            await connect()
        }
    }

    func stop() {
        Task {
            await engine?.stop()
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

    private func connect() async {
        connectionState = .starting
        do {
            let privateKey = try dependencies.keyStore.loadPrivateKeyData(keyRefId: host.keyRefId)
            let prompter = SSHHostKeyPrompt { [weak self] hostKey in
                guard let self else { return false }
                return await self.promptForHostKey(hostKey)
            }
            let connectInfo = try await dependencies.moshBootstrapper.bootstrap(
                host: host,
                privateKey: privateKey,
                passphrase: nil,
                hostKeyPrompter: prompter
            )

            let engine = dependencies.moshEngineFactory()
            self.engine = engine

            engine.onOutput = { [weak controller] data in
                Task { @MainActor in
                    controller?.feedOutput(data)
                }
            }

            engine.onStateChange = { [weak self] state in
                Task { @MainActor in
                    self?.connectionState = state
                }
            }

            controller?.onInput = { [weak engine] data in
                Task {
                    await engine?.sendInput(data)
                }
            }

            controller?.onSizeChange = { [weak engine] size in
                Task {
                    await engine?.updateTerminalSize(cols: size.cols, rows: size.rows)
                }
            }

            let size = controller?.currentSize ?? TerminalSize(cols: 80, rows: 24)
            try await engine.start(connectInfo: connectInfo, initialTerminalSize: size)
        } catch {
            connectionState = .failed(.startFailed(message: error.localizedDescription))
            alertMessage = error.localizedDescription
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
