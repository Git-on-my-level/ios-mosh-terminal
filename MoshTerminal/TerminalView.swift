import SwiftUI
import SwiftTerm

private typealias TerminalUIKitView = SwiftTerm.TerminalView

struct TerminalView: View {
    let host: String
    @StateObject private var controller = TerminalLoopbackController()

    var body: some View {
        TerminalContainerView(controller: controller)
            .onTapGesture {
                controller.focus()
            }
            .navigationTitle(host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    TerminalAccessoryRow(controller: controller)
                }
            }
    }
}

private struct TerminalContainerView: UIViewRepresentable {
    @ObservedObject var controller: TerminalLoopbackController

    func makeUIView(context: Context) -> TerminalUIKitView {
        let view = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        )
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = UIColor.black
        view.nativeForegroundColor = UIColor.white
        view.backgroundColor = UIColor.black
        controller.attach(view: view)
        DispatchQueue.main.async {
            controller.seedIfNeeded()
            controller.focus()
        }
        return view
    }

    func updateUIView(_ uiView: TerminalUIKitView, context: Context) {
        if controller.terminalView !== uiView {
            controller.attach(view: uiView)
        }
    }

    func makeCoordinator() -> TerminalLoopbackController {
        controller
    }
}

private struct TerminalAccessoryRow: View {
    @ObservedObject var controller: TerminalLoopbackController

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

final class TerminalLoopbackController: NSObject, ObservableObject, TerminalViewDelegate {
    @Published var isCtrlActive = false
    private var hasSeeded = false
    weak var terminalView: TerminalUIKitView?

    func attach(view: TerminalUIKitView) {
        terminalView = view
    }

    func seedIfNeeded() {
        guard let terminalView, !hasSeeded else {
            return
        }
        hasSeeded = true
        terminalView.feed(text: "Loopback mode: input echoes locally.\n")
        terminalView.feed(text: "> ")
    }

    func focus() {
        terminalView?.becomeFirstResponder()
    }

    func toggleCtrl() {
        isCtrlActive.toggle()
    }

    func sendText(_ text: String) {
        terminalView?.send(txt: text)
    }

    func sendControl(_ byte: UInt8) {
        terminalView?.send([byte])
    }

    // MARK: - TerminalViewDelegate
    func sizeChanged(source: TerminalUIKitView, newCols: Int, newRows: Int) {}
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
            source.feed(byteArray: transformed[...])
        } else {
            source.feed(byteArray: data)
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

#Preview {
    NavigationStack {
        TerminalView(host: "Preview")
    }
}
