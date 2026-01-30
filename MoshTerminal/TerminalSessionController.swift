import Foundation
import SwiftTerm

typealias TerminalUIKitView = SwiftTerm.TerminalView

final class TerminalSessionController: NSObject, ObservableObject, TerminalViewDelegate {
    @Published var isCtrlActive = false

    weak var terminalView: TerminalUIKitView?
    var onInput: (@Sendable (Data) -> Void)?
    var onSizeChange: (@Sendable (TerminalSize) -> Void)?

    private(set) var currentSize = TerminalSize(cols: 80, rows: 24)
    private var pendingRemoteResize: TerminalSize?

    func attach(view: TerminalUIKitView) {
        terminalView = view
    }

    func focus() {
        terminalView?.becomeFirstResponder()
    }

    func toggleCtrl() {
        isCtrlActive.toggle()
    }

    func sendText(_ text: String) {
        onInput?(Data(text.utf8))
    }

    func sendControl(_ byte: UInt8) {
        onInput?(Data([byte]))
    }

    func feedOutput(_ data: Data) {
        let bytes = Array(data)
        terminalView?.feed(byteArray: bytes[...])
    }

    func applyRemoteResize(cols: Int, rows: Int) {
        let size = TerminalSize(cols: cols, rows: rows)
        guard size != currentSize else { return }
        currentSize = size
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
            onInput?(Data(transformed))
        } else {
            onInput?(Data(data))
        }
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

    private func controlByte(for byte: UInt8) -> UInt8? {
        if (byte >= 0x40 && byte <= 0x5F) || (byte >= 0x61 && byte <= 0x7A) {
            return byte & 0x1F
        }
        return nil
    }
}
