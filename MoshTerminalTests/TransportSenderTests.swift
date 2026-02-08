import XCTest
@testable import MoshClientCore
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

    func testTransportSenderDoesNotEvictUnackedStatesWhenAtCap() {
        let sender = TransportSender()
        sender.setConnected(true, nowMillis: 0)

        let maxStates = TransportSender.Constants.maxSentStates
        for index in 0..<maxStates {
            sender.currentState.append(.keystroke(Data([UInt8(0x41 + index % 26)])))
            _ = sender.tick(nowMillis: UInt64((index + 1) * 20))
        }

        XCTAssertEqual(sender.sentStates.count, maxStates)
        XCTAssertEqual(sender.sentStates.first?.num, 1)
        XCTAssertEqual(sender.sentStates.last?.num, UInt64(maxStates))

        sender.currentState.append(.keystroke(Data([0x7A])))
        _ = sender.tick(nowMillis: UInt64((maxStates + 1) * 20))

        XCTAssertEqual(sender.sentStates.count, maxStates)
        XCTAssertEqual(sender.sentStates.first?.num, 1)
        XCTAssertEqual(sender.sentStates.last?.num, UInt64(maxStates))
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
        let instructions = sender.tick(nowMillis: timeout)
        if !instructions.isEmpty {
            XCTAssertTrue(instructions.allSatisfy { $0.diff.isEmpty })
        }
    }

    func testTransportSenderEmitsKeepaliveWhenIdle() {
        let sender = TransportSender(keepaliveIntervalMillis: 100)
        sender.setConnected(true, nowMillis: 0)

        XCTAssertTrue(sender.tick(nowMillis: 0).isEmpty)

        let instructions = sender.tick(nowMillis: 100)
        XCTAssertEqual(instructions.count, 1)
        XCTAssertTrue(instructions[0].diff.isEmpty)
        XCTAssertEqual(instructions[0].ackNum, 0)
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

    func testTransportSenderHandlesRNGFailureGracefully() {
        let failingRng = FailingRandomSource()
        let sender = TransportSender(randomBytes: failingRng.next)
        sender.setConnected(true, nowMillis: 0)
        sender.currentState.append(.keystroke(Data("a".utf8)))

        let instructions = sender.tick(nowMillis: 8)
        XCTAssertEqual(instructions.count, 1)
        XCTAssertEqual(instructions[0].chaff, Data())
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

private final class FailingRandomSource {
    func next(count: Int) -> [UInt8] {
        return []
    }
}
