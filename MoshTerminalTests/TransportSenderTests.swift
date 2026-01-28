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

        sender.processAckThrough(1)

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
}
