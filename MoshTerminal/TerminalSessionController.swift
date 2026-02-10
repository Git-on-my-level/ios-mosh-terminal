import Foundation
import Prediction
import SwiftTerm
import UIKit

typealias TerminalUIKitView = SwiftTerm.TerminalView

@MainActor
final class TerminalSessionController: NSObject, ObservableObject, @preconcurrency TerminalViewDelegate, UIScrollViewDelegate {
    @Published var isCtrlActive = false

    var terminalView: TerminalUIKitView?
    var onInput: (@Sendable (Data) -> Void)?
    var onSizeChange: (@Sendable (TerminalSize) -> Void)?

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
    private var pendingRemoteResize: TerminalSize?

    private var isUserScrolledAwayFromBottom: Bool = false
    private var lastUserContentOffset: CGPoint?
    private var isAdjustingScrollOffset: Bool = false

    private var pendingSizeChange: DispatchWorkItem?
    private var lastSizeSentToEngine: TerminalSize?

    private weak var altBufferPanGesture: UIPanGestureRecognizer?

    private var pendingOutputData = Data()
    private var pendingOutputFlush: DispatchWorkItem?
    private var outputBuffer = [UInt8]()

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

        isUserScrolledAwayFromBottom = false
        lastUserContentOffset = nil

        pendingSizeChange?.cancel()
        pendingSizeChange = nil
        lastSizeSentToEngine = nil

        if let gesture = altBufferPanGesture, let view = existingTerminalView {
            view.removeGestureRecognizer(gesture)
        }
        altBufferPanGesture = nil

        pendingOutputFlush?.cancel()
        pendingOutputFlush = nil
        pendingOutputData.removeAll(keepingCapacity: false)
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

    func focus() {
        _ = terminalView?.becomeFirstResponder()
    }

    func toggleCtrl() {
        isCtrlActive.toggle()
    }

    func sendText(_ text: String) {
        forwardUserInput(Data(text.utf8))
    }

    func sendControl(_ byte: UInt8) {
        forwardUserInput(Data([byte]))
    }

    func feedOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        pendingOutputData.append(data)
        scheduleOutputFlush()
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
    func scrolled(source: TerminalUIKitView, position: Double) {}
    func requestOpenLink(source: TerminalUIKitView, link: String, params: [String: String]) {}
    func bell(source: TerminalUIKitView) {}
    func clipboardCopy(source: TerminalUIKitView, content: Data) {}
    func iTermContent(source: TerminalUIKitView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalUIKitView, startY: Int, endY: Int) {}

    func send(source: TerminalUIKitView, data: ArraySlice<UInt8>) {
        if let transformed = applyCtrlIfNeeded(data) {
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
        // In SwiftTerm, alternate buffer disables scrollback and reports thumb size 0.
        // When that happens, map vertical swipe/pan into PageUp/PageDown escape sequences.
        guard terminalView.scrollThumbsize == 0 else { return }
        guard gesture.state == .ended else { return }

        let translation = gesture.translation(in: terminalView)
        let velocity = gesture.velocity(in: terminalView)
        gesture.setTranslation(.zero, in: terminalView)

        // Trigger on either a meaningful swipe distance or a fast flick.
        let threshold: CGFloat = 40
        let velocityThreshold: CGFloat = 600
        if translation.y <= -threshold || velocity.y <= -velocityThreshold {
            terminalView.pageUp()
        } else if translation.y >= threshold || velocity.y >= velocityThreshold {
            terminalView.pageDown()
        }
    }
}
