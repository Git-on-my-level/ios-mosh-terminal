import XCTest
@testable import MoshTerminal

final class ProtoCodecTests: XCTestCase {
    func testProtoReaderRejectsTruncatedVarint() {
        var reader = ProtoReader(data: Data([0x80]))
        XCTAssertThrowsError(try reader.readVarint()) { error in
            XCTAssertEqual(error as? ProtoCodecError, .truncated)
        }
    }

    func testProtoReaderRejectsMalformedVarint() {
        let data = Data(repeating: 0x80, count: 10)
        var reader = ProtoReader(data: data)
        XCTAssertThrowsError(try reader.readVarint()) { error in
            XCTAssertEqual(error as? ProtoCodecError, .malformedVarint)
        }
    }

    func testProtoReaderRejectsInvalidFieldNumber() {
        var reader = ProtoReader(data: Data([0x00]))
        XCTAssertThrowsError(try reader.readKey()) { error in
            XCTAssertEqual(error as? ProtoCodecError, .invalidWireType)
        }
    }

    func testProtoReaderRejectsLengthOverflow() {
        var writer = ProtoWriter()
        writer.writeVarint(UInt64(Int.max) + 1)
        var reader = ProtoReader(data: writer.data)
        XCTAssertThrowsError(try reader.readLengthDelimited()) { error in
            XCTAssertEqual(error as? ProtoCodecError, .lengthOverflow)
        }
    }
}
