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
    @StateObject private var keyboardObserver = KeyboardObserver()
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isVisible = false
    @State private var passphraseInput = ""
    @State private var lastConnectionState: ConnectionManager.State = .idle
    @State private var wantsReconnectPrompt = false
    @State private var terminalViewId = UUID()
    @State private var openURLCandidate: URL?

    init(host: HostProfile, dependencies: TerminalSessionDependencies, autoConnect: Bool = true) {
        self.host = host
        self.autoConnect = autoConnect
        let controller = dependencies.connectionManager.controller(for: host)
        _controller = StateObject(wrappedValue: controller)
        _viewModel = StateObject(wrappedValue: TerminalSessionViewModel(host: host, dependencies: dependencies, controller: controller))
        _connectionManager = ObservedObject(wrappedValue: dependencies.connectionManager)
    }

    var body: some View {
        let palette = AppTheme.terminalPalette(for: colorScheme)
        let colors = AppTheme.colors(for: colorScheme)
        TerminalContainerView(controller: controller, fontSize: settings.fontSize, palette: palette, isKeyboardVisible: keyboardObserver.isKeyboardVisible)
            .id(terminalViewId)
            .onReceive(controller.$pendingOpenURL) { url in
                if let url {
                    openURLCandidate = url
                    controller.pendingOpenURL = nil
                }
            }
            .alert("Open Link?", isPresented: Binding(
                get: { openURLCandidate != nil },
                set: { if !$0 { openURLCandidate = nil } }
            )) {
                Button("Cancel", role: .cancel) { openURLCandidate = nil }
                Button("Open") {
                    if let url = openURLCandidate { openURL(url) }
                    openURLCandidate = nil
                }
            } message: {
                Text(openURLCandidate?.absoluteString ?? "")
            }
            .onChange(of: settings.predictionDisplayPreference) { _ in
                updatePredictionPreference()
            }
#if DEBUG
            .onChange(of: settings.debugPredictionEnabled) { _ in
                updatePredictionPreference()
            }
#endif
            .onTapGesture {
                controller.focus()
            }
            .navigationTitle(host.resolvedDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if shouldShowReconnectAction {
                        Button {
                            wantsReconnectPrompt = false
                            viewModel.retry()
                        } label: {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .accessibilityLabel("Reconnect")
                    } else {
                        Button(role: .destructive) {
                            wantsReconnectPrompt = true
                            controller.reset()
                            terminalViewId = UUID()
                            viewModel.stop()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .accessibilityLabel("Disconnect")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
#if DEBUG
                    if settings.debugOverlayEnabled {
                        TerminalDebugOverlay(connectionManager: connectionManager, controller: controller)
                    }
#endif
                    if !keyboardObserver.isKeyboardVisible {
                        Button {
                            controller.focus()
                        } label: {
                            Image(systemName: "keyboard")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(colors.accent)
                                .frame(width: 52, height: 52)
                                .background(colors.surfaceElevated)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(colors.divider, lineWidth: 1))
                                .shadow(color: colors.divider.opacity(0.6), radius: 6, x: 0, y: 3)
                        }
                        .accessibilityLabel("Show keyboard")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: keyboardObserver.isKeyboardVisible)
            }
            .onAppear {
                isVisible = true
                wantsReconnectPrompt = false
                updatePredictionPreference()
                controller.resetPredictions()
                updateIdleTimer()
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                    viewModel.start(autoConnect: autoConnect)
                }
            }
            .onDisappear {
                isVisible = false
                controller.resetPredictions()
                updateIdleTimer()
            }
            .onChange(of: settings.keepAwake) { _ in
                updateIdleTimer()
            }
            .onChange(of: connectionManager.state) { newState in
                triggerConnectionHaptic(from: lastConnectionState, to: newState)
                lastConnectionState = newState
                switch newState {
                case .connected, .bootstrappingSSH, .connectingUDP, .reconnecting:
                    wantsReconnectPrompt = false
                case .disconnected, .failed:
                    wantsReconnectPrompt = true
                case .idle:
                    break
                }
                if newState == .connected, isVisible {
                    DispatchQueue.main.async {
                        controller.focus()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    TerminalStatusBar(
                        state: connectionManager.state,
                        palette: palette
                    )
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
            .toolbarBackground(colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

    private func updatePredictionPreference() {
        var preference = settings.predictionDisplayPreference
#if DEBUG
        if settings.debugPredictionEnabled {
            preference = .always
        }
#endif
        controller.setPredictionDisplayPreference(preference)
    }

    private var shouldShowReconnectAction: Bool {
        switch connectionManager.state {
        case .disconnected, .failed:
            return true
        case .idle:
            return wantsReconnectPrompt
        default:
            return wantsReconnectPrompt
        }
    }

    private func triggerConnectionHaptic(from oldState: ConnectionManager.State, to newState: ConnectionManager.State) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        switch (oldState, newState) {
        case (.connected, .disconnected), (.connected, .failed), (.connected, .idle):
            generator.impactOccurred()
        case (_, .connected):
            generator.impactOccurred()
        default:
            break
        }
    }
}

#if DEBUG
private struct TerminalDebugOverlay: View {
    @ObservedObject var connectionManager: ConnectionManager
    let controller: TerminalSessionController
    @State private var snapshot: ConnectionManager.DebugSnapshot?
    @State private var predictionSnapshot: PredictionDebugMetrics?
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
            Text("Unreachable sends: \(snapshot?.consecutiveUnreachableSends.map(String.init) ?? "n/a")")
            if let net = snapshot?.predictionNetwork {
                Divider()
                Text("Sent: \(net.lastSentStateNum)")
                Text("Acked: \(net.lastAckedStateNum)")
                Text("EchoAck: \(net.echoAck)")
                Text("SRTT: \(net.srttMillis.map { "\($0)ms" } ?? "n/a")")
            }
            if let predictionSnapshot {
                Divider()
                Text("Pred send: \(predictionSnapshot.sendIntervalMillis)ms")
                Text("Pred echoAck: \(predictionSnapshot.echoAck)")
                Text("Pred srttTrigger: \(predictionSnapshot.srttTrigger ? "on" : "off")")
                Text("Pred glitch: \(predictionSnapshot.glitchTrigger)")
                Text("Pred active: \(predictionSnapshot.activePredictionCount)")
            }
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
            predictionSnapshot = controller.predictionDebugSnapshot()
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

/// Detects when this view is removed from a navigation stack (popped).
/// This is more reliable than `onDisappear`, since switching tabs also triggers `onDisappear`.
private struct NavigationPopDetector: UIViewControllerRepresentable {
    let onPop: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        PopObserverController(onPop: onPop)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class PopObserverController: UIViewController {
    private let onPop: () -> Void

    init(onPop: @escaping () -> Void) {
        self.onPop = onPop
        super.init(nibName: nil, bundle: nil)
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent ||
            parent?.isMovingFromParent == true ||
            isBeingDismissed ||
            parent?.isBeingDismissed == true {
            onPop()
        }
    }
}

/// Bridges SwiftTerm's UIKit-based TerminalView into SwiftUI.
///
/// ## Keyboard Accessory Visibility
/// The custom keyboard accessory (Esc, Ctrl, ^C, arrows, etc.) must only appear when
/// the system keyboard is visible. We achieve this by:
/// 1. Tracking keyboard visibility via `KeyboardObserver` in the parent view
/// 2. Passing `isKeyboardVisible` to this view
/// 3. Dynamically setting `inputAccessoryView` to our custom view or `nil`
///
/// **Why not just use `inputAccessoryView` directly?**
/// UIKit's `inputAccessoryView` normally hides with the keyboard, but SwiftTerm's
/// TerminalView has custom first-responder handling that can cause the accessory
/// to persist on screen even when the keyboard is dismissed. By explicitly setting
/// it to `nil` when the keyboard hides, we guarantee correct behavior.
private struct TerminalContainerView: UIViewRepresentable {
    @ObservedObject var controller: TerminalSessionController
    let fontSize: Double
    let palette: AppTheme.TerminalPalette
    let isKeyboardVisible: Bool

    func makeUIView(context: Context) -> TerminalUIKitView {
        let terminalView: TerminalUIKitView
        let reusedView = controller.terminalView != nil
        if let cachedView = controller.terminalView {
            cachedView.removeFromSuperview()
            terminalView = cachedView
        } else {
            terminalView = StableTerminalView(
                frame: .zero,
                font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            )
        }
        terminalView.terminalDelegate = context.coordinator
        applyPalette(palette, to: terminalView)
        controller.attach(view: terminalView)
        let overlayView = installPredictionOverlay(in: terminalView, controller: controller, replaceExisting: reusedView)
        overlayView.predictionTextColor = UIColor(palette.foreground)
        overlayView.predictionBackgroundColor = UIColor(palette.background)
        if reusedView {
            controller.resetPredictions()
            terminalView.setNeedsLayout()
            terminalView.layoutIfNeeded()
            terminalView.setNeedsDisplay()
        }
        context.coordinator.accessoryView = TerminalAccessoryHostingView(controller: controller)
        terminalView.inputAccessoryView = nil

        DispatchQueue.main.async {
            controller.focus()
        }
        return terminalView
    }

    func updateUIView(_ terminalView: TerminalUIKitView, context: Context) {
        if controller.terminalView !== terminalView {
            controller.attach(view: terminalView)
        }
        if terminalView.terminalDelegate !== context.coordinator {
            terminalView.terminalDelegate = context.coordinator
        }
        if terminalView.font.pointSize != CGFloat(fontSize) {
            terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        applyPalette(palette, to: terminalView)
        let overlayView = installPredictionOverlay(in: terminalView, controller: controller)
        overlayView.predictionTextColor = UIColor(palette.foreground)
        overlayView.predictionBackgroundColor = UIColor(palette.background)

        if context.coordinator.accessoryView == nil {
            context.coordinator.accessoryView = TerminalAccessoryHostingView(controller: controller)
        }
        let expectedAccessory: UIView? = isKeyboardVisible ? context.coordinator.accessoryView : nil
        if terminalView.inputAccessoryView !== expectedAccessory {
            terminalView.inputAccessoryView = expectedAccessory
            terminalView.reloadInputViews()
        }
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

// IMPORTANT: The prediction overlay must be a subview of SwiftTerm's TerminalUIKitView.
// Wrapping TerminalUIKitView in a container view regressed UDP connectivity.
@MainActor
@discardableResult
func installPredictionOverlay(
    in terminalView: TerminalUIKitView,
    controller: TerminalSessionController,
    replaceExisting: Bool = false
) -> PredictionOverlayView {
    let overlayTag = 0x4D4F5348 // "MOSH"
    if replaceExisting, let existing = terminalView.viewWithTag(overlayTag) as? PredictionOverlayView {
        existing.removeFromSuperview()
    }
    if let existing = terminalView.viewWithTag(overlayTag) as? PredictionOverlayView {
        existing.font = terminalView.font
        existing.layer.zPosition = 1000
        // TerminalUIKitView is a UIScrollView; its bounds origin changes as it scrolls.
        // Keep the overlay aligned to the visible region when SwiftUI reuses the view, otherwise
        // predictions can be rendered off-screen and appear to "stop" until reconnect.
        existing.frame = terminalView.bounds
        controller.predictionOverlayView = existing
        terminalView.bringSubviewToFront(existing)
        return existing
    }

    let overlayView = PredictionOverlayView()
    overlayView.tag = overlayTag
    overlayView.layer.zPosition = 1000
    overlayView.translatesAutoresizingMaskIntoConstraints = true
    overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlayView.frame = terminalView.bounds
    overlayView.isUserInteractionEnabled = false
    overlayView.font = terminalView.font
    terminalView.addSubview(overlayView)
    terminalView.bringSubviewToFront(overlayView)
    controller.predictionOverlayView = overlayView
    return overlayView
}

/// UIKit hosting view that wraps the SwiftUI TerminalAccessoryRow for use as inputAccessoryView
private final class TerminalAccessoryHostingView: UIInputView {
    private let hostingController: UIHostingController<TerminalAccessoryRow>
    private static let accessoryHeight: CGFloat = 44

    init(controller: TerminalSessionController) {
        let accessoryRow = TerminalAccessoryRow(controller: controller)
        self.hostingController = UIHostingController(rootView: accessoryRow)

        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: Self.accessoryHeight),
                   inputViewStyle: .keyboard)

        hostingController.view.backgroundColor = .clear
        backgroundColor = .clear

        addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.heightAnchor.constraint(equalToConstant: Self.accessoryHeight)
        ])

        autoresizingMask = [.flexibleWidth]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.accessoryHeight)
    }
}

/// Custom keyboard accessory bar providing terminal-specific keys.
///
/// ## Main Row (default)
/// - **Modifiers**: Esc, Ctrl (toggle), Tab
/// - **Direct Ctrl shortcuts**: ^C (interrupt), ^D (EOF), ^Z (suspend), ^L (clear), ^A (start of line), ^E (end of line)
/// - **Symbols**: ~, |, /, -
/// - **Navigation**: Arrow keys (←, ↓, ↑, →)
///
/// ## Function Keys Row (via F1-9 toggle)
/// - F1 through F10
///
/// The Ctrl toggle allows sending any Ctrl+key combination by tapping Ctrl then a letter on the main keyboard.
/// Direct ^C/^D/etc. buttons provide single-tap access to the most common control sequences.
private struct TerminalAccessoryRow: View {
    @ObservedObject var controller: TerminalSessionController
    @State private var showFunctionKeys = false

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                if showFunctionKeys {
                    functionKeysRow
                } else {
                    mainKeysRow
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Toggle F-keys / keyboard dismiss
            HStack(spacing: 4) {
                Button {
                    hapticFeedback.impactOccurred()
                    showFunctionKeys.toggle()
                } label: {
                    Text(showFunctionKeys ? "ABC" : "F1-9")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Button {
                    hapticFeedback.impactOccurred()
                    controller.terminalView?.resignFirstResponder()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .onAppear {
            hapticFeedback.prepare()
        }
    }

    private var mainKeysRow: some View {
        HStack(spacing: 4) {
            // Modifier keys
            accessoryButton("Esc") {
                controller.sendControl(0x1B)
            }
            accessoryButton("Ctrl", isActive: controller.isCtrlActive) {
                controller.toggleCtrl()
            }
            accessoryButton("Tab") {
                controller.sendControl(0x09)
            }

            Divider()
                .frame(height: 20)

            // Common Ctrl+key shortcuts (most used)
            ctrlKeyButton("C") // Ctrl+C (interrupt)
            ctrlKeyButton("D") // Ctrl+D (EOF)
            ctrlKeyButton("Z") // Ctrl+Z (suspend)
            ctrlKeyButton("L") // Ctrl+L (clear)
            ctrlKeyButton("A") // Ctrl+A (start of line)
            ctrlKeyButton("E") // Ctrl+E (end of line)

            Divider()
                .frame(height: 20)

            // Common symbols
            accessoryButton("~") {
                controller.sendText("~")
            }
            accessoryButton("|") {
                controller.sendText("|")
            }
            accessoryButton("/") {
                controller.sendText("/")
            }
            accessoryButton("-") {
                controller.sendText("-")
            }

            Divider()
                .frame(height: 20)

            // Arrow keys
            arrowButton("arrow.left") {
                controller.sendText("\u{1b}[D")
            }
            arrowButton("arrow.down") {
                controller.sendText("\u{1b}[B")
            }
            arrowButton("arrow.up") {
                controller.sendText("\u{1b}[A")
            }
            arrowButton("arrow.right") {
                controller.sendText("\u{1b}[C")
            }
        }
        .padding(.horizontal, 8)
    }

    /// Creates a button that sends Ctrl+<key> directly
    private func ctrlKeyButton(_ key: String) -> some View {
        Button {
            hapticFeedback.impactOccurred()
            // Convert letter to control character (A=1, B=2, ..., Z=26)
            if let char = key.uppercased().first,
               let ascii = char.asciiValue {
                let ctrlByte = ascii & 0x1F
                controller.sendControl(ctrlByte)
            }
        } label: {
            Text("^\(key)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }

    private var functionKeysRow: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { num in
                accessoryButton("F\(num)") {
                    // F1-F10 escape sequences
                    let sequences = [
                        "\u{1b}OP", "\u{1b}OQ", "\u{1b}OR", "\u{1b}OS",
                        "\u{1b}[15~", "\u{1b}[17~", "\u{1b}[18~", "\u{1b}[19~",
                        "\u{1b}[20~", "\u{1b}[21~"
                    ]
                    controller.sendText(sequences[num - 1])
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func accessoryButton(_ title: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            hapticFeedback.impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .orange : nil)
    }

    private func arrowButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            hapticFeedback.impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }
}

private struct TerminalStatusBar: View {
    let state: ConnectionManager.State
    let palette: AppTheme.TerminalPalette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(state.shortStatusText)
                .font(AppTheme.typography.caption)
                .foregroundStyle(colors.primaryText)
            if showsProgress {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(statusColor)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(palette.statusBarBackground)
        .overlay(alignment: .bottom) {
            Divider()
                .background(colors.divider)
        }
    }

    private var statusColor: SwiftUI.Color {
        let colors = AppTheme.colors(for: colorScheme)
        switch state {
        case .connected:
            return colors.statusConnected
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return colors.statusConnecting
        case .failed, .disconnected:
            return colors.statusError
        case .idle:
            return colors.secondaryText
        }
    }

    private var showsProgress: Bool {
        switch state {
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return true
        default:
            return false
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
            if let helpInfo = failure.helpInfo {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                    Text("Learn more")
                        .font(.caption2)
                        .underline()
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.8))
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = helpInfo
                }
            }
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

/// Observes keyboard visibility changes using NotificationCenter.
///
/// Used by `TerminalView` to control when the custom keyboard accessory bar is shown.
/// The accessory bar must only appear when the system keyboard is visible to avoid
/// blocking the tab bar or appearing during navigation transitions.
///
/// - SeeAlso: `TerminalContainerView` documentation for the full visibility mechanism.
private final class KeyboardObserver: ObservableObject {
    @Published private(set) var isKeyboardVisible = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = false
            }
            .store(in: &cancellables)
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
