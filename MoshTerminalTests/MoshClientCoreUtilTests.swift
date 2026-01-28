import XCTest
@testable import MoshTerminal

final class MoshClientCoreUtilTests: XCTestCase {
    func testSessionKeyDecode22Chars() throws {
        let bytes = Array(UInt8(0)..<UInt8(16))
        let base64 = Data(bytes).base64EncodedString()
        XCTAssertEqual(base64.count, 24)
        let printable = String(base64.dropLast(2))

        let decoded = try SessionKey.decode(printable)

        XCTAssertEqual(decoded, bytes)
    }

    func testSessionKeyDecodeRejectsInvalidLength() {
        XCTAssertThrowsError(try SessionKey.decode("short")) { error in
            XCTAssertEqual(error as? SessionKeyError, .invalidLength)
        }
    }

    func testSessionKeyDecodeRejectsInvalidBase64() {
        let invalid = String(repeating: "!", count: 22)
        XCTAssertThrowsError(try SessionKey.decode(invalid)) { error in
            XCTAssertEqual(error as? SessionKeyError, .invalidBase64)
        }
    }

    func testTimestamp16NeverReturnsMax() {
        let samples: [UInt64] = [0, 1, 65534, 65535, 65536, 131071, 131072]
        for millis in samples {
            let value = Clock.timestamp16(fromMillis: millis)
            XCTAssertNotEqual(value, UInt16.max)
        }
    }

    func testSequenceCounterMonotonic() {
        let counter = SequenceCounter()
        XCTAssertEqual(counter.next(), 0)
        XCTAssertEqual(counter.next(), 1)
        XCTAssertEqual(counter.next(), 2)
    }
}
