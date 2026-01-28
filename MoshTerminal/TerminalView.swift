import Combine
import SwiftUI
import SwiftTerm
import UIKit

struct TerminalView: View {
    let host: HostProfile
    let autoConnect: Bool
    @ObservedObject private var connectionManager: ConnectionManager
    @StateObject private var controller: TerminalSessionController
    @StateObject private var viewModel: TerminalSessionViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var isVisible = false
    @State private var passphraseInput = ""

    init(host: HostProfile, dependencies: TerminalSessionDependencies, autoConnect: Bool = true) {
        self.host = host
        self.autoConnect = autoConnect
        let controller = TerminalSessionController()
        _controller = StateObject(wrappedValue: controller)
        _viewModel = StateObject(wrappedValue: TerminalSessionViewModel(host: host, dependencies: dependencies, controller: controller))
        _connectionManager = ObservedObject(wrappedValue: dependencies.connectionManager)
    }

    var body: some View {
        let palette = AppTheme.terminalPalette(for: colorScheme)
        TerminalContainerView(controller: controller, fontSize: settings.fontSize, palette: palette)
            .onTapGesture {
                controller.focus()
            }
            .navigationTitle(host.resolvedDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect", role: .destructive) {
                        viewModel.stop()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    TerminalAccessoryRow(controller: controller)
                }
            }
            .overlay(alignment: .bottomTrailing) {
#if DEBUG
                if settings.debugOverlayEnabled {
                    TerminalDebugOverlay(connectionManager: connectionManager)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
#endif
            }
            .onAppear {
                isVisible = true
                updateIdleTimer()
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                    viewModel.start(autoConnect: autoConnect)
                }
            }
            .onDisappear {
                isVisible = false
                updateIdleTimer()
                viewModel.stop()
            }
            .onChange(of: settings.keepAwake) { _ in
                updateIdleTimer()
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    TerminalStatusBar(state: connectionManager.state, palette: palette)
                    if let failure = viewModel.failure {
                        TerminalErrorBanner(
                            failure: failure,
                            onRetry: { viewModel.retry() },
                            onBack: {
                                viewModel.dismissFailure()
                                viewModel.stop()
                                dismiss()
                            }
                        )
                    }
                }
            }
            .alert(item: $viewModel.hostKeyPrompt) { prompt in
                Alert(
                    title: Text("Trust Host Key?"),
                    message: Text("\(prompt.hostKey.hostname):\(prompt.hostKey.port)\n\(prompt.hostKey.fingerprint)"),
                    primaryButton: .default(Text("Trust")) {
                        viewModel.respondToHostKeyPrompt(shouldTrust: true)
                    },
                    secondaryButton: .cancel {
                        viewModel.respondToHostKeyPrompt(shouldTrust: false)
                    }
                )
            }
            .alert(
                "SSH Key Passphrase",
                isPresented: Binding(
                    get: { viewModel.passphrasePrompt != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.respondToPassphrasePrompt(passphrase: nil)
                        }
                    }
                )
            ) {
                SecureField("Passphrase", text: $passphraseInput)
                Button("Cancel", role: .cancel) {
                    viewModel.respondToPassphrasePrompt(passphrase: nil)
                    passphraseInput = ""
                }
                Button("Connect") {
                    let submitted = passphraseInput
                    viewModel.respondToPassphrasePrompt(passphrase: submitted)
                    passphraseInput = ""
                }
            } message: {
                if let prompt = viewModel.passphrasePrompt {
                    Text(passphraseMessage(prompt.context))
                }
            }
            .onChange(of: viewModel.passphrasePrompt?.id) { _ in
                passphraseInput = ""
            }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isVisible && settings.keepAwake
    }

    private func passphraseMessage(_ context: SSHKeyPassphraseContext) -> String {
        let hostLine = "\(context.username)@\(context.hostname)"
        if context.hostDisplayName.isEmpty || context.hostDisplayName == context.hostname {
            return "\(context.keyLabel)\n\(hostLine)"
        }
        return "\(context.keyLabel)\n\(context.hostDisplayName)\n\(hostLine)"
    }
}

#if DEBUG
private struct TerminalDebugOverlay: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var snapshot: ConnectionManager.DebugSnapshot?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug")
                .font(.caption2)
                .bold()
            Text("State: \(connectionManager.state.statusText)")
            Text("Last heard: \(formatAge(snapshot?.lastHeardAgeMillis))")
            Text("Send interval: \(formatMillis(snapshot?.sendIntervalMillis))")
            Text("RTO: \(formatMillis(snapshot?.rtoMillis))")
            Text("Local UDP: \(snapshot?.localPort.map(String.init) ?? "n/a")")
        }
        .font(.caption2)
        .padding(8)
        .background(Color.black.opacity(0.7))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            refresh()
        }
        .onReceive(timer) { _ in
            refresh()
        }
    }

    private func refresh() {
        Task { @MainActor in
            snapshot = await connectionManager.debugSnapshot()
        }
    }

    private func formatAge(_ millis: UInt64?) -> String {
        guard let millis else { return "n/a" }
        let seconds = Double(millis) / 1000.0
        return "\(String(format: "%.1f", seconds))s"
    }

    private func formatMillis(_ millis: UInt64?) -> String {
        guard let millis else { return "n/a" }
        return "\(millis)ms"
    }
}
#endif

private struct TerminalContainerView: UIViewRepresentable {
    @ObservedObject var controller: TerminalSessionController
    let fontSize: Double
    let palette: AppTheme.TerminalPalette

    func makeUIView(context: Context) -> TerminalUIKitView {
        let view = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        )
        view.terminalDelegate = context.coordinator
        applyPalette(palette, to: view)
        controller.attach(view: view)
        DispatchQueue.main.async {
            controller.focus()
        }
        return view
    }

    func updateUIView(_ uiView: TerminalUIKitView, context: Context) {
        if controller.terminalView !== uiView {
            controller.attach(view: uiView)
        }
        if uiView.font.pointSize != CGFloat(fontSize) {
            uiView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        applyPalette(palette, to: uiView)
    }

    func makeCoordinator() -> TerminalSessionController {
        controller
    }

    private func applyPalette(_ palette: AppTheme.TerminalPalette, to view: TerminalUIKitView) {
        let background = UIColor(palette.background)
        let foreground = UIColor(palette.foreground)
        if view.nativeBackgroundColor != background {
            view.nativeBackgroundColor = background
        }
        if view.nativeForegroundColor != foreground {
            view.nativeForegroundColor = foreground
        }
        if view.backgroundColor != background {
            view.backgroundColor = background
        }
    }
}

private struct TerminalAccessoryRow: View {
    @ObservedObject var controller: TerminalSessionController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                accessoryButton("Esc") {
                    controller.sendControl(0x1B)
                }
                Button {
                    controller.toggleCtrl()
                } label: {
                    Text("Ctrl")
                        .frame(minWidth: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isCtrlActive ? .orange : .secondary)
                accessoryButton("Tab") {
                    controller.sendControl(0x09)
                }
                accessoryButton("|") {
                    controller.sendText("|")
                }
                accessoryButton("-") {
                    controller.sendText("-")
                }
                accessoryButton("/") {
                    controller.sendText("/")
                }
                accessoryButton(":") {
                    controller.sendText(":")
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accessoryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(minWidth: 28)
        }
        .buttonStyle(.bordered)
    }
}

private struct TerminalStatusBar: View {
    let state: ConnectionManager.State
    let palette: AppTheme.TerminalPalette

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(state.shortStatusText)
                .font(.caption2)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(palette.statusBarBackground)
    }

    private var statusColor: SwiftUI.Color {
        switch state {
        case .connected:
            return SwiftUI.Color.green
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return SwiftUI.Color.orange
        case .failed, .disconnected:
            return SwiftUI.Color.red
        case .idle:
            return SwiftUI.Color.secondary
        }
    }
}

private struct TerminalErrorBanner: View {
    let failure: ConnectionFailure
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(failure.title)
                .font(.caption)
                .foregroundStyle(.white)
                .bold()
            Text(failure.message)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 8) {
                if failure.allowsRetry {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.9))
                }
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.9))
                Spacer()
            }
            .font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.85))
    }
}

#Preview {
    let host = HostProfile(displayName: "Preview", hostname: "preview.local", username: "user", keyRefId: "preview-key")
    let store = JSONStore()
    let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
    let sshClientFactory = DefaultSSHClientFactory.make(repository: trustedHostKeyRepository)
    let keyStore = KeychainPrivateKeyStore()
    let moshBootstrapper = MoshBootstrapper(sshClientFactory: sshClientFactory)
    let appLifecycleService = AppLifecycleService()
    let networkPathService = NetworkPathService()
    let hostRepository = HostRepository(store: store)
    let connectionManager = ConnectionManager(
        keyStore: keyStore,
        hostRepository: hostRepository,
        moshBootstrapper: moshBootstrapper,
        moshEngineFactory: { LoopbackMoshEngine() },
        appLifecycleService: appLifecycleService,
        networkPathService: networkPathService
    )
    let dependencies = TerminalSessionDependencies(connectionManager: connectionManager)
    NavigationStack {
        TerminalView(host: host, dependencies: dependencies, autoConnect: false)
    }
    .environmentObject(AppSettings())
}
