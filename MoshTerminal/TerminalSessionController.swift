import Foundation
import Prediction
import SwiftTerm
import UIKit

typealias TerminalUIKitView = SwiftTerm.TerminalView

@MainActor
final class TerminalSessionController: NSObject, ObservableObject, @preconcurrency TerminalViewDelegate, UIScrollViewDelegate {
    @Published var isCtrlActive = false
    @Published var isAltActive = false
    @Published var pendingOpenURL: URL?

    override init() {
        super.init()
        StartupDiagnostics.shared.incrementTerminalSessionControllerInit()
    }

    var terminalView: TerminalUIKitView?
    var onInput: (@Sendable (Data) -> Void)?
    var onSizeChange: (@Sendable (TerminalSize) -> Void)?
    var onRequestFontSizeDelta: ((Int) -> Void)?

    /// Holds the keyboard accessory view for reuse across keyboard show/hide cycles.
    /// Set by `TerminalContainerView.makeUIView` and attached/detached in `updateUIView`
    /// based on keyboard visibility. See `TerminalContainerView` docs for details.
    var accessoryView: UIView?

    /// Holds a reference to the prediction overlay view for updating render models.
    var predictionOverlayView: PredictionOverlayView? {
        didSet {
            predictionCoordinator.overlayView = predictionOverlayView
        }
    }

    private let predictionCoordinator = TerminalPredictionCoordinator()

    private(set) var currentSize = TerminalSize(cols: 80, rows: 24)
    private(set) var isBracketedPasteEnabled = false
    private var pendingRemoteResize: TerminalSize?

    private var isUserScrolledAwayFromBottom: Bool = false
    private var lastUserContentOffset: CGPoint?
    private var isAdjustingScrollOffset: Bool = false

    private var pendingSizeChange: DispatchWorkItem?
    private var lastSizeSentToEngine: TerminalSize?

    private weak var altBufferPanGesture: UIPanGestureRecognizer?
    fileprivate var altBufferScrollOffset: CGFloat = 0
    fileprivate var scrollCommandCount: Int = 0
    private let maxScrollCommandsPerGesture: Int = 50
    fileprivate var lastScrollDirectionChangeTime: Date = .distantPast
    private let scrollDirectionChangeDebounceMs: Int = 50

    private var pendingOutputData = Data()
    private var pendingOutputFlush: DispatchWorkItem?
    private var outputBuffer = [UInt8]()
    private var bracketProbe = Data()
    private let bracketEnable = Data([0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x68]) // ESC[?2004h
    private let bracketDisable = Data([0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x6C]) // ESC[?2004l
    private var pinchAccumulatedScale: CGFloat = 1.0
    private let pinchThreshold: CGFloat = 0.15
    private var autoFocusSuppressionUntil: Date = .distantPast

    func reset() {
        let existingTerminalView = terminalView
        terminalView = nil
        accessoryView = nil
        if let overlayView = predictionOverlayView {
            overlayView.removeFromSuperview()
        }
        predictionOverlayView = nil
        predictionCoordinator.terminalView = nil
        predictionCoordinator.reset()

        pinchAccumulatedScale = 1.0

        isUserScrolledAwayFromBottom = false
        lastUserContentOffset = nil

        pendingSizeChange?.cancel()
        pendingSizeChange = nil
        lastSizeSentToEngine = nil

        if let gesture = altBufferPanGesture, let view = existingTerminalView {
            view.removeGestureRecognizer(gesture)
        }
        altBufferPanGesture = nil
        altBufferScrollOffset = 0
        scrollCommandCount = 0
        lastScrollDirectionChangeTime = .distantPast

        pendingOutputFlush?.cancel()
        pendingOutputFlush = nil
        pendingOutputData.removeAll(keepingCapacity: false)
        autoFocusSuppressionUntil = .distantPast
    }

    @objc func handleTerminalPinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchAccumulatedScale = 1.0
        case .changed:
            let scale = gesture.scale
            gesture.scale = 1.0
            pinchAccumulatedScale *= scale

            if pinchAccumulatedScale > 1.0 + pinchThreshold {
                onRequestFontSizeDelta?(+1)
                pinchAccumulatedScale = 1.0
            } else if pinchAccumulatedScale < 1.0 - pinchThreshold {
                onRequestFontSizeDelta?(-1)
                pinchAccumulatedScale = 1.0
            }
        case .ended, .cancelled:
            pinchAccumulatedScale = 1.0
        default:
            break
        }
    }

    func attach(view: TerminalUIKitView) {
        terminalView = view
        view.delegate = self
        predictionCoordinator.terminalView = view
        installAltBufferPagingGestureIfNeeded(in: view)
    }

    func attachPredictionNetworkProvider(_ provider: PredictionNetworkSnapshotProviding?) {
        predictionCoordinator.predictionNetworkProvider = provider
    }

    func setPredictionDisplayPreference(_ preference: PredictionDisplayPreference) {
        predictionCoordinator.setDisplayPreference(preference)
    }

    func predictionDebugSnapshot() -> PredictionDebugMetrics {
        predictionCoordinator.debugSnapshot()
    }

    func resetPredictions() {
        predictionCoordinator.reset()
    }

    func focus(force: Bool = false) {
        if !force, Date() < autoFocusSuppressionUntil {
            return
        }
        _ = terminalView?.becomeFirstResponder()
    }

    func dismissKeyboard() {
        // Prevent immediate re-focus from async view/state callbacks while dismissal is in-flight.
        autoFocusSuppressionUntil = Date().addingTimeInterval(0.75)
        _ = terminalView?.resignFirstResponder()
    }

    func toggleCtrl() {
        isCtrlActive.toggle()
    }

    func toggleAlt() {
        isAltActive.toggle()
    }

    func sendText(_ text: String) {
        forwardUserInput(Data(text.utf8))
    }

    func sendControl(_ byte: UInt8) {
        forwardUserInput(Data([byte]))
    }

    func pasteFromClipboard() {
        guard let string = UIPasteboard.general.string, !string.isEmpty else { return }
        sendPasteData(preparedPasteData(from: string))
    }

    func preparedPasteData(from string: String) -> Data {
        let normalized = string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r")

        let isMultiline = string.contains("\n") || string.contains("\r")
        if isMultiline, isBracketedPasteEnabled {
            let start = "\u{1B}[200~"
            let end = "\u{1B}[201~"
            return Data((start + normalized + end).utf8)
        }
        return Data(normalized.utf8)
    }

    private func sendPasteData(_ data: Data) {
        let chunkSize = 4096
        let interChunkDelayNs: UInt64 = 2_000_000

        guard data.count > chunkSize else {
            forwardUserInput(data)
            return
        }

        predictionCoordinator.reset()

        Task { @MainActor in
            var idx = data.startIndex
            while idx < data.endIndex {
                let end = min(idx + chunkSize, data.endIndex)
                forwardUserInput(data.subdata(in: idx..<end))
                idx = end
                try? await Task.sleep(nanoseconds: interChunkDelayNs)
            }
        }
    }

    func feedOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        updateBracketedPasteMode(with: data)
        pendingOutputData.append(data)
        scheduleOutputFlush()
    }

    private func updateBracketedPasteMode(with output: Data) {
        guard !output.isEmpty else { return }

        var probe = bracketProbe
        probe.append(output)

        let lastEnableIndex = probe.lastRange(of: bracketEnable)?.lowerBound
        let lastDisableIndex = probe.lastRange(of: bracketDisable)?.lowerBound
        if let enableIndex = lastEnableIndex, let disableIndex = lastDisableIndex {
            isBracketedPasteEnabled = enableIndex > disableIndex
        } else if lastEnableIndex != nil {
            isBracketedPasteEnabled = true
        } else if lastDisableIndex != nil {
            isBracketedPasteEnabled = false
        }

        let overlap = max(bracketEnable.count, bracketDisable.count) - 1
        if probe.count > overlap {
            bracketProbe = Data(probe.suffix(overlap))
        } else {
            bracketProbe = probe
        }
    }

    func applyRemoteResize(cols: Int, rows: Int) {
        let size = TerminalSize(cols: cols, rows: rows)
        guard size != currentSize else { return }
        currentSize = size
        predictionCoordinator.handleResize(cols: cols, rows: rows)
        guard let terminalView else { return }
        pendingRemoteResize = size
        // Avoid SwiftTerm's `TerminalView.resize(cols:rows:)` helper since it performs a DECSTR soft reset,
        // which can clear/reset TUI state. We only want to resize the emulator grid and refresh the view.
        let terminal = terminalView.getTerminal()
        terminal.resize(cols: cols, rows: rows)
        terminalView.sizeChanged(source: terminal)
        terminalView.setNeedsDisplay(terminalView.bounds)
    }

    // MARK: - TerminalViewDelegate
    func sizeChanged(source: TerminalUIKitView, newCols: Int, newRows: Int) {
        let size = TerminalSize(cols: newCols, rows: newRows)
        currentSize = size
        
        altBufferScrollOffset = 0
        scrollCommandCount = 0
        
        if let pending = pendingRemoteResize {
            pendingRemoteResize = nil
            if pending == size {
                return
            }
        }
        predictionCoordinator.handleResize(cols: newCols, rows: newRows)

        // Layout changes can emit multiple sizeChanged callbacks in quick succession (rotation, keyboard).
        // Coalesce the remote resize updates so we don't thrash TUIs with rapid SIGWINCH.
        let hadPending = (pendingSizeChange != nil)
        pendingSizeChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastSizeSentToEngine = size
            self.onSizeChange?(size)
        }
        pendingSizeChange = work
        let isInitial = (lastSizeSentToEngine == nil && !hadPending)
        let delay: TimeInterval = isInitial ? 0 : 0.075
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func setTerminalTitle(source: TerminalUIKitView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalUIKitView, directory: String?) {}
    func scrolled(source: TerminalUIKitView, position: Double) {
        if position < 0.999 {
            predictionCoordinator.reset()
        }
    }
    func requestOpenLink(source: TerminalUIKitView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
        pendingOpenURL = url
    }
    func bell(source: TerminalUIKitView) {}
    func clipboardCopy(source: TerminalUIKitView, content: Data) {
        guard !content.isEmpty else { return }

        let string = String(data: content, encoding: .utf8)
            ?? String(decoding: content, as: UTF8.self)

        UIPasteboard.general.string = string

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        #if DEBUG
        DebugLogger.shared.logClipboardCopy(bytes: content.count)
        #endif
    }
    func iTermContent(source: TerminalUIKitView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalUIKitView, startY: Int, endY: Int) {}

    func send(source: TerminalUIKitView, data: ArraySlice<UInt8>) {
        if let transformed = applyCtrlIfNeeded(data) {
            forwardUserInput(Data(transformed))
        } else if let transformed = applyAltIfNeeded(data) {
            forwardUserInput(Data(transformed))
        } else {
            forwardUserInput(Data(data))
        }
    }

    private func forwardUserInput(_ data: Data) {
        guard !data.isEmpty else { return }
        if data.count > 100 {
            predictionCoordinator.reset()
        } else {
            predictionCoordinator.handleUserInput(data: data)
        }
        onInput?(data)
    }

    private func applyCtrlIfNeeded(_ data: ArraySlice<UInt8>) -> [UInt8]? {
        guard isCtrlActive, data.count == 1, let byte = data.first else {
            return nil
        }
        guard let ctrlByte = controlByte(for: byte) else {
            return nil
        }
        return [ctrlByte]
    }

    private func applyAltIfNeeded(_ data: ArraySlice<UInt8>) -> [UInt8]? {
        guard isAltActive, data.count == 1, let byte = data.first else {
            return nil
        }
        guard (0x20...0x7E).contains(byte) else {
            return nil
        }
        return [0x1B, byte]
    }

    func handleEchoAckUpdated() {
        predictionCoordinator.handleEchoAckUpdated()
    }

    private func scheduleOutputFlush() {
        if pendingOutputFlush != nil {
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingOutputFlush = nil
            self.flushPendingOutput()
        }
        pendingOutputFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0), execute: work)

        // If output bursts get large, flush sooner to avoid high latency before paint.
        if pendingOutputData.count >= 32 * 1024 {
            pendingOutputFlush?.cancel()
            pendingOutputFlush = nil
            flushPendingOutput()
        }
    }

    private func flushPendingOutput() {
        guard let terminalView else {
            pendingOutputData.removeAll(keepingCapacity: false)
            return
        }
        guard !pendingOutputData.isEmpty else { return }

        let preserveOffset = isUserScrolledAwayFromBottom
        let preservedOffset = lastUserContentOffset ?? terminalView.contentOffset

        let count = pendingOutputData.count
        if outputBuffer.count < count {
            outputBuffer = Array(repeating: 0, count: count)
        }
        pendingOutputData.copyBytes(to: &outputBuffer, count: count)
        pendingOutputData.removeAll(keepingCapacity: true)

        isAdjustingScrollOffset = preserveOffset
        terminalView.feed(byteArray: outputBuffer[..<count])
        predictionCoordinator.handleConfirmedOutputApplied()

        if preserveOffset {
            terminalView.setContentOffset(clampContentOffset(preservedOffset, in: terminalView), animated: false)
        }
        isAdjustingScrollOffset = false
    }

    private func controlByte(for byte: UInt8) -> UInt8? {
        if (byte >= 0x40 && byte <= 0x5F) || (byte >= 0x61 && byte <= 0x7A) {
            return byte & 0x1F
        }
        return nil
    }

    // MARK: - UIScrollViewDelegate
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === terminalView else { return }
        guard !isAdjustingScrollOffset else { return }
        let wasAway = isUserScrolledAwayFromBottom
        let away = !isAtBottom(scrollView)
        isUserScrolledAwayFromBottom = away
        lastUserContentOffset = away ? scrollView.contentOffset : nil
        if away && !wasAway {
            // Hide predictions while the user is reading history to avoid visual overlap.
            predictionCoordinator.reset()
        }
    }

    private func isAtBottom(_ scrollView: UIScrollView) -> Bool {
        let maxOffsetY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        guard let terminalView else {
            return scrollView.contentOffset.y >= maxOffsetY
        }
        let metrics = TerminalGridSizer.metrics(for: terminalView.font)
        return scrollView.contentOffset.y >= (maxOffsetY - metrics.cellHeight)
    }

    private func clampContentOffset(_ offset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        return CGPoint(
            x: min(max(offset.x, 0), maxX),
            y: min(max(offset.y, 0), maxY)
        )
    }

    // MARK: - Alt Buffer Paging
    private func installAltBufferPagingGestureIfNeeded(in terminalView: TerminalUIKitView) {
        if let existing = altBufferPanGesture, terminalView.gestureRecognizers?.contains(existing) == true {
            return
        }
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleAltBufferPagingPan(_:)))
        gesture.cancelsTouchesInView = false
        terminalView.addGestureRecognizer(gesture)
        altBufferPanGesture = gesture
    }

    @objc private func handleAltBufferPagingPan(_ gesture: UIPanGestureRecognizer) {
        guard let terminalView else { return }
        guard terminalView.scrollThumbsize == 0 else { return }

        switch gesture.state {
        case .began:
            altBufferScrollOffset = 0
            scrollCommandCount = 0
            lastScrollDirectionChangeTime = .distantPast
        case .changed:
            guard scrollCommandCount < maxScrollCommandsPerGesture else { return }
            
            let now = Date()
            let elapsedMs = Int(now.timeIntervalSince(lastScrollDirectionChangeTime) * 1000)
            if elapsedMs < scrollDirectionChangeDebounceMs && scrollCommandCount > 0 {
                return
            }
            
            let translation = gesture.translation(in: terminalView)
            gesture.setTranslation(.zero, in: terminalView)
            
            let previousOffset = altBufferScrollOffset
            altBufferScrollOffset += translation.y
            
            let scrollPixelsPerPage: CGFloat = 200
            let scrollThreshold: CGFloat = 40
            
            if altBufferScrollOffset <= -scrollThreshold {
                if previousOffset > -scrollThreshold {
                    lastScrollDirectionChangeTime = now
                }
                let pagesToScroll = Int(-altBufferScrollOffset / scrollPixelsPerPage)
                let commandsToSend = min(pagesToScroll, maxScrollCommandsPerGesture - scrollCommandCount)
                for _ in 0..<commandsToSend {
                    terminalView.pageUp()
                    scrollCommandCount += 1
                }
                altBufferScrollOffset = fmod(altBufferScrollOffset, scrollPixelsPerPage)
            } else if altBufferScrollOffset >= scrollThreshold {
                if previousOffset < scrollThreshold {
                    lastScrollDirectionChangeTime = now
                }
                let pagesToScroll = Int(altBufferScrollOffset / scrollPixelsPerPage)
                let commandsToSend = min(pagesToScroll, maxScrollCommandsPerGesture - scrollCommandCount)
                for _ in 0..<commandsToSend {
                    terminalView.pageDown()
                    scrollCommandCount += 1
                }
                altBufferScrollOffset = fmod(altBufferScrollOffset, scrollPixelsPerPage)
            }
        case .ended, .cancelled:
            altBufferScrollOffset = 0
            scrollCommandCount = 0
        default:
            break
        }
    }
}
