import Foundation

final class DebugLogBuffer {
    static let shared = DebugLogBuffer()

    private let queue = DispatchQueue(label: "com.moshterminal.debuglog.buffer")
    private var lines: [String] = []
    private let maxLines = 500

    func append(_ line: String) {
        queue.async { [maxLines] in
            self.lines.append(line)
            if self.lines.count > maxLines {
                self.lines.removeFirst(self.lines.count - maxLines)
            }
        }
    }

    func snapshot() -> [String] {
        queue.sync { lines }
    }

    func clear() {
        queue.sync { lines.removeAll() }
    }
}
