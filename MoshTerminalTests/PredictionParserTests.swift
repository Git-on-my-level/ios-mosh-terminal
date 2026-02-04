import XCTest
@testable import MoshTerminal

final class PredictionParserTests: XCTestCase {
    var parser: UTF8ByteParser!

    override func setUp() {
        super.setUp()
        parser = UTF8ByteParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    func testASCIILetters() {
        let data = Data("Hello".utf8)
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 5)
        XCTAssertEqual(actions[0], .print("H", width: 1))
        XCTAssertEqual(actions[1], .print("e", width: 1))
        XCTAssertEqual(actions[2], .print("l", width: 1))
        XCTAssertEqual(actions[3], .print("l", width: 1))
        XCTAssertEqual(actions[4], .print("o", width: 1))
    }

    func testBackspace() {
        let data = Data([0x7F])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .backspace)
    }

    func testCarriageReturn() {
        let data = Data([0x0D])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .carriageReturn)
    }

    func testControlCharactersAreUnknown() {
        let controlChars: [UInt8] = [0x00, 0x01, 0x02, 0x1A]
        for char in controlChars {
            let data = Data([char])
            let actions = parser.feed(data)
            XCTAssertEqual(actions.count, 1)
            XCTAssertEqual(actions[0], .unknown, "Control character 0x\(String(char, radix: 16)) should be unknown")
        }
    }

    func testArrowLeftCSI() {
        let data = Data([0x1B, 0x5B, 0x44])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .arrowLeft)
    }

    func testArrowRightCSI() {
        let data = Data([0x1B, 0x5B, 0x43])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .arrowRight)
    }

    func testArrowLeftSS3() {
        let data = Data([0x1B, 0x4F, 0x44])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .arrowLeft)
    }

    func testArrowRightSS3() {
        let data = Data([0x1B, 0x4F, 0x43])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .arrowRight)
    }

    func testArrowWithParameter() {
        let data = Data([0x1B, 0x5B, 0x33, 0x44])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .arrowLeft)
    }

    func testArrowWithMultipleParameters() {
        let data = Data([0x1B, 0x5B, 0x31, 0x3B, 0x32, 0x43])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .arrowRight)
    }

    func testUTF8TwoByteCharacter() {
        let data = Data("é".utf8)
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testUTF8ThreeByteCharacter() {
        let data = Data("€".utf8)
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testUTF8FourByteCharacter() {
        let data = Data("😀".utf8)
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testMixedUTF8Characters() {
        let text = "a€b😀c"
        let data = Data(text.utf8)
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 5)
        XCTAssertEqual(actions[0], .print("a", width: 1))
        XCTAssertEqual(actions[1], .unknown)
        XCTAssertEqual(actions[2], .print("b", width: 1))
        XCTAssertEqual(actions[3], .unknown)
        XCTAssertEqual(actions[4], .print("c", width: 1))
    }

    func testSplitArrowSequence() {
        let data1 = Data([0x1B])
        let data2 = Data([0x5B])
        let data3 = Data([0x44])

        let actions1 = parser.feed(data1)
        XCTAssertEqual(actions1.count, 0)

        let actions2 = parser.feed(data2)
        XCTAssertEqual(actions2.count, 0)

        let actions3 = parser.feed(data3)
        XCTAssertEqual(actions3.count, 1)
        XCTAssertEqual(actions3[0], .arrowLeft)
    }

    func testSplitUTF8Character() {
        let data = Data("é".utf8)

        let splitIndex = data.count / 2
        let chunk1 = data.prefix(splitIndex)
        let chunk2 = data.suffix(from: splitIndex)

        let actions1 = parser.feed(Data(chunk1))
        XCTAssertEqual(actions1.count, 0)

        let actions2 = parser.feed(Data(chunk2))
        XCTAssertEqual(actions2.count, 1)
        XCTAssertEqual(actions2[0], .unknown)
    }

    func testMultipleFeedCalls() {
        let data1 = Data("Hel".utf8)
        let data2 = Data("lo".utf8)

        let actions1 = parser.feed(data1)
        XCTAssertEqual(actions1.count, 3)

        let actions2 = parser.feed(data2)
        XCTAssertEqual(actions2.count, 2)

        XCTAssertEqual(actions1[0], .print("H", width: 1))
        XCTAssertEqual(actions1[1], .print("e", width: 1))
        XCTAssertEqual(actions1[2], .print("l", width: 1))
        XCTAssertEqual(actions2[0], .print("l", width: 1))
        XCTAssertEqual(actions2[1], .print("o", width: 1))
    }

    func testComplexInputSplit() {
        let input: [UInt8] = [0x61, 0x62, 0x7F, 0x63, 0x64, 0x1B, 0x5B, 0x44, 0x65]

        let chunk1 = input.prefix(3)
        let chunk2 = input.dropFirst(3).prefix(3)
        let chunk3 = input.dropFirst(6).prefix(3)
        let chunk4 = input.dropFirst(9)

        let actions1 = parser.feed(Data(chunk1))
        XCTAssertEqual(actions1.count, 3)
        XCTAssertEqual(actions1[0], .print("a", width: 1))
        XCTAssertEqual(actions1[1], .print("b", width: 1))
        XCTAssertEqual(actions1[2], .backspace)

        let actions2 = parser.feed(Data(chunk2))
        XCTAssertEqual(actions2.count, 2)
        XCTAssertEqual(actions2[0], .print("c", width: 1))
        XCTAssertEqual(actions2[1], .print("d", width: 1))

        let actions3 = parser.feed(Data(chunk3))
        XCTAssertEqual(actions3.count, 2)
        XCTAssertEqual(actions3[0], .arrowLeft)
        XCTAssertEqual(actions3[1], .print("e", width: 1))

        let actions4 = parser.feed(Data(chunk4))
        XCTAssertEqual(actions4.count, 0)
    }

    func testUnknownEscapeSequence() {
        let data = Data([0x1B, 0x50])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testUnknownCSISequence() {
        let data = Data([0x1B, 0x5B, 0x41])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testUnknownSS3Sequence() {
        let data = Data([0x1B, 0x4F, 0x50])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testInvalidUTF8Continuation() {
        let data = Data([0xC2, 0x00])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testInvalidUTF8Sequence() {
        let data = Data([0xC0, 0x80])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .unknown)
    }

    func testResetClearsState() {
        let data1 = Data([0x1B])
        _ = parser.feed(data1)

        parser.reset()

        let data2 = Data([0x61])
        let actions = parser.feed(data2)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .print("a", width: 1))
    }

    func testResetDuringUTF8Decoding() {
        let data1 = Data([0xC2])
        _ = parser.feed(data1)

        parser.reset()

        let data2 = Data([0x61, 0x62])
        let actions = parser.feed(data2)

        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0], .print("a", width: 1))
        XCTAssertEqual(actions[1], .print("b", width: 1))
    }

    func testEmptyInput() {
        let data = Data()
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 0)
    }

    func testSpaceCharacter() {
        let data = Data([0x20])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .print(" ", width: 1))
    }

    func testTildeCharacter() {
        let data = Data([0x7E])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .print("~", width: 1))
    }

    func testCSIWithIntermediateCharacter() {
        let data = Data([0x1B, 0x5B, 0x3B, 0x44])
        let actions = parser.feed(data)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0], .arrowLeft)
    }
}
