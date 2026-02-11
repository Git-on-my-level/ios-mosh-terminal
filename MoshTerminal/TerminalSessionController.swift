import Foundation
import SwiftTerm
import UIKit

typealias TerminalUIKitView = SwiftTerm.TerminalView

final class TerminalSessionController: NSObject, ObservableObject, TerminalViewDelegate {
    @Published var isCtrlActive = false
    @Published var isAltActive = false
    @Published var pendingOpenURL: URL?

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
    private var outputBuffer = [UInt8]()
    private var bracketProbe = Data()
    private let bracketEnable = Data([0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x68]) // ESC[?2004h
    private let bracketDisable = Data([0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x6C]) // ESC[?2004l
    private var pinchAccumulatedScale: CGFloat = 1.0
    private let pinchThreshold: CGFloat = 0.15

    func reset() {
        terminalView = nil
        accessoryView = nil
        if let overlayView = predictionOverlayView {
            overlayView.removeFromSuperview()
        }
        predictionOverlayView = nil
        predictionCoordinator.terminalView = nil
        predictionCoordinator.reset()
        pinchAccumulatedScale = 1.0
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
        predictionCoordinator.terminalView = view
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
        terminalView?.becomeFirstResponder()
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
        if outputBuffer.count < data.count {
            outputBuffer = Array(repeating: 0, count: data.count)
        }
        data.copyBytes(to: &outputBuffer, count: data.count)
        terminalView?.feed(byteArray: outputBuffer[..<data.count])
        predictionCoordinator.handleConfirmedOutputApplied()
    }

    private func updateBracketedPasteMode(with output: Data) {
        let maxProbe = 64
        bracketProbe.append(output)
        if bracketProbe.count > maxProbe {
            bracketProbe.removeFirst(bracketProbe.count - maxProbe)
        }

        if bracketProbe.range(of: bracketEnable) != nil {
            isBracketedPasteEnabled = true
            bracketProbe.removeAll(keepingCapacity: true)
        } else if bracketProbe.range(of: bracketDisable) != nil {
            isBracketedPasteEnabled = false
            bracketProbe.removeAll(keepingCapacity: true)
        }
    }

    func applyRemoteResize(cols: Int, rows: Int) {
        let size = TerminalSize(cols: cols, rows: rows)
        guard size != currentSize else { return }
        currentSize = size
        predictionCoordinator.handleResize(cols: cols, rows: rows)
        guard let terminalView else { return }
        pendingRemoteResize = size
        terminalView.resize(cols: cols, rows: rows)
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
        onSizeChange?(size)
        predictionCoordinator.handleResize(cols: newCols, rows: newRows)
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

    private func controlByte(for byte: UInt8) -> UInt8? {
        if (byte >= 0x40 && byte <= 0x5F) || (byte >= 0x61 && byte <= 0x7A) {
            return byte & 0x1F
        }
        return nil
    }
}
