import XCTest
@testable import MoshTerminal

final class TransportSenderTests: XCTestCase {
    func testTransportSenderSendsDiffOnNewState() throws {
        let sender = TransportSender()
        sender.setConnected(true, nowMillis: 0)
        sender.currentState.append(.keystroke(Data("a".utf8)))

        let instructions = sender.tick(nowMillis: 8)
        XCTAssertEqual(instructions.count, 1)
        let instruction = instructions[0]
        XCTAssertEqual(instruction.protocolVersion, 2)
        XCTAssertFalse(instruction.diff.isEmpty)
        XCTAssertEqual(instruction.oldNum, 0)
        XCTAssertEqual(instruction.newNum, 1)
    }

    func testTransportSenderDropsAckedStates() {
        let sender = TransportSender()
        sender.setConnected(true, nowMillis: 0)

        sender.currentState.append(.keystroke(Data("a".utf8)))
        _ = sender.tick(nowMillis: 8)

        sender.currentState.append(.keystroke(Data("b".utf8)))
        _ = sender.tick(nowMillis: 28)

        sender.processAckThrough(1, nowMillis: 28)

        XCTAssertEqual(sender.sentStates.count, 1)
        XCTAssertEqual(sender.sentStates.first?.num, 2)
    }

    func testTransportSenderEmitsAckOnlyOnSchedule() {
        let sender = TransportSender()
        sender.setConnected(true, nowMillis: 0)
        sender.setAckNum(7)

        XCTAssertTrue(sender.tick(nowMillis: 0).isEmpty)
        XCTAssertTrue(sender.tick(nowMillis: 50).isEmpty)

        let instructions = sender.tick(nowMillis: 100)
        XCTAssertEqual(instructions.count, 1)
        let instruction = instructions[0]
        XCTAssertEqual(instruction.ackNum, 7)
        XCTAssertTrue(instruction.diff.isEmpty)
        XCTAssertEqual(instruction.oldNum, 0)
        XCTAssertEqual(instruction.newNum, 0)
    }

    func testTransportSenderWaitTimeWhenNotConnected() {
        let sender = TransportSender()
        XCTAssertEqual(sender.waitTime(nowMillis: 0), Int.max)
    }

    func testTransportSenderResendsAfterMaxInterval() {
        let rng = DeterministicRandomSource(bytes: [0])
        let sender = TransportSender(randomBytes: rng.next)
        sender.setConnected(true, nowMillis: 0)
        sender.currentState.append(.keystroke(Data("a".utf8)))

        let first = sender.tick(nowMillis: 8)
        XCTAssertEqual(first.count, 1)

        XCTAssertTrue(sender.tick(nowMillis: 200).isEmpty)

        let resendTime = UInt64(8) + TransportSender.Constants.maxSendIntervalMillis
        let resent = sender.tick(nowMillis: resendTime)
        XCTAssertEqual(resent.count, 1)
        XCTAssertEqual(resent[0].oldNum, 0)
        XCTAssertEqual(resent[0].newNum, 1)
        XCTAssertFalse(resent[0].diff.isEmpty)
    }

    func testTransportSenderStopsResendAfterActiveRetryTimeout() {
        let rng = DeterministicRandomSource(bytes: [0])
        let sender = TransportSender(randomBytes: rng.next)
        sender.setConnected(true, nowMillis: 0)
        sender.currentState.append(.keystroke(Data("a".utf8)))

        _ = sender.tick(nowMillis: 8)

        let timeout = UInt64(8) + TransportSender.Constants.activeRetryTimeoutMillis + 1
        XCTAssertTrue(sender.tick(nowMillis: timeout).isEmpty)
    }

    func testTransportSenderUsesDeterministicChaff() {
        let rng = DeterministicRandomSource(bytes: [5, 1, 2, 3, 4, 5])
        let sender = TransportSender(randomBytes: rng.next)
        sender.setConnected(true, nowMillis: 0)
        sender.currentState.append(.keystroke(Data("a".utf8)))

        let instructions = sender.tick(nowMillis: 8)
        XCTAssertEqual(instructions.count, 1)
        XCTAssertEqual(instructions[0].chaff, Data([1, 2, 3, 4, 5]))
    }
}

private final class DeterministicRandomSource {
    private var bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    func next(count: Int) -> [UInt8] {
        guard count > 0 else {
            return []
        }
        if bytes.count < count {
            let padding = [UInt8](repeating: 0, count: count - bytes.count)
            let slice = bytes + padding
            bytes.removeAll()
            return slice
        }
        let slice = Array(bytes.prefix(count))
        bytes.removeFirst(count)
        return slice
    }
}
