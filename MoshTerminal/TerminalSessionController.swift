import Foundation
import SwiftTerm
import UIKit

typealias TerminalUIKitView = SwiftTerm.TerminalView

@MainActor
final class TerminalSessionController: NSObject, ObservableObject, TerminalViewDelegate {
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
    private var outputBuffer = [UInt8]()

    func reset() {
        terminalView = nil
        accessoryView = nil
        if let overlayView = predictionOverlayView {
            overlayView.removeFromSuperview()
        }
        predictionOverlayView = nil
        predictionCoordinator.terminalView = nil
        predictionCoordinator.reset()
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

    func sendText(_ text: String) {
        forwardUserInput(Data(text.utf8))
    }

    func sendControl(_ byte: UInt8) {
        forwardUserInput(Data([byte]))
    }

    func feedOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        if outputBuffer.count < data.count {
            outputBuffer = Array(repeating: 0, count: data.count)
        }
        data.copyBytes(to: &outputBuffer, count: data.count)
        terminalView?.feed(byteArray: outputBuffer[..<data.count])
        predictionCoordinator.handleConfirmedOutputApplied()
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

    private func controlByte(for byte: UInt8) -> UInt8? {
        if (byte >= 0x40 && byte <= 0x5F) || (byte >= 0x61 && byte <= 0x7A) {
            return byte & 0x1F
        }
        return nil
    }
}
