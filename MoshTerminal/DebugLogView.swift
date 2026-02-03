import SwiftUI

struct DebugLogView: View {
    @State private var lines: [String] = []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("log")
            }
            .background(Color(.systemBackground))
            .onAppear {
                refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("log", anchor: .bottom)
                }
            }
            .onReceive(timer) { _ in
                refresh()
                proxy.scrollTo("log", anchor: .bottom)
            }
        }
        .navigationTitle("Debug Logs")
        .toolbar {
            Button("Clear") {
                DebugLogBuffer.shared.clear()
                refresh()
            }
        }
    }

    private func refresh() {
        lines = DebugLogBuffer.shared.snapshot()
    }
}

#Preview {
    NavigationStack {
        DebugLogView()
    }
}
