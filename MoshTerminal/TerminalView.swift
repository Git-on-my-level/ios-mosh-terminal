import SwiftUI
import SwiftTerm
import UIKit

private typealias TerminalUIKitView = SwiftTerm.TerminalView

struct TerminalView: View {
    let host: HostProfile
    let autoConnect: Bool
    @ObservedObject private var connectionManager: ConnectionManager
    @StateObject private var controller: TerminalSessionController
    @StateObject private var viewModel: TerminalSessionViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var isVisible = false

    init(host: HostProfile, dependencies: TerminalSessionDependencies, autoConnect: Bool = true) {
        self.host = host
        self.autoConnect = autoConnect
        let controller = TerminalSessionController()
        _controller = StateObject(wrappedValue: controller)
        _viewModel = StateObject(wrappedValue: TerminalSessionViewModel(host: host, dependencies: dependencies, controller: controller))
        _connectionManager = ObservedObject(wrappedValue: dependencies.connectionManager)
    }

    var body: some View {
        TerminalContainerView(controller: controller, fontSize: settings.fontSize)
            .onTapGesture {
                controller.focus()
            }
            .navigationTitle(host.resolvedDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    TerminalAccessoryRow(controller: controller)
                }
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
                TerminalStatusBar(state: connectionManager.state)
            }
            .alert(
                "Terminal",
                isPresented: Binding(
                    get: { viewModel.alertMessage != nil },
                    set: { _ in viewModel.dismissAlert() }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "")
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
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isVisible && settings.keepAwake
    }
}

private struct TerminalContainerView: UIViewRepresentable {
    @ObservedObject var controller: TerminalSessionController
    let fontSize: Double

    func makeUIView(context: Context) -> TerminalUIKitView {
        let view = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        )
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = UIColor.black
        view.nativeForegroundColor = UIColor.white
        view.backgroundColor = UIColor.black
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
        if uiView.font?.pointSize != fontSize {
            uiView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    func makeCoordinator() -> TerminalSessionController {
        controller
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
        .background(Color.black.opacity(0.7))
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return .orange
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
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
    let connectionManager = ConnectionManager(
        keyStore: keyStore,
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
