import Foundation

final class SequenceCounter {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        if value == UInt64.max {
            preconditionFailure("SequenceCounter overflow")
        }
        let current = value
        value += 1
        return current
    }
}
