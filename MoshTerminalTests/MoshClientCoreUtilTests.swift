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

    func testZlibRoundTripSizes() throws {
        let sizes = [0, 1, 1024, 64 * 1024]
        for size in sizes {
            var bytes = [UInt8](repeating: 0, count: size)
            for index in 0..<size {
                bytes[index] = UInt8(truncatingIfNeeded: index)
            }
            let input = Data(bytes)
            let compressed = try ZlibCodec.compress(input)
            let decompressed = try ZlibCodec.decompress(compressed)
            XCTAssertEqual(decompressed, input)
        }
    }

    func testZlibRejectsRandomBytes() {
        let random = Data(repeating: 0xFF, count: 64)
        XCTAssertThrowsError(try ZlibCodec.decompress(random)) { error in
            XCTAssertNotNil(error as? ZlibCodecError)
        }
    }

    func testZlibRejectsOutputOverLimit() throws {
        let maxOutput = 1024
        let payload = Data(repeating: 0, count: maxOutput * 2)
        let compressed = try ZlibCodec.compress(payload)
        XCTAssertThrowsError(try ZlibCodec.decompress(compressed, maxOutputBytes: maxOutput)) { error in
            XCTAssertEqual(error as? ZlibCodecError, .outputTooLarge(max: maxOutput))
        }
    }

    func testTransportInstructionRoundTripRandomized() throws {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let diffSize = Int.random(in: 0...512, using: &rng)
            let chaffSize = Int.random(in: 0...512, using: &rng)
            let instruction = TransportInstruction(
                protocolVersion: UInt32.random(in: 0...UInt32.max, using: &rng),
                oldNum: UInt64.random(in: 0...UInt64.max, using: &rng),
                newNum: UInt64.random(in: 0...UInt64.max, using: &rng),
                ackNum: UInt64.random(in: 0...UInt64.max, using: &rng),
                throwawayNum: UInt64.random(in: 0...UInt64.max, using: &rng),
                diff: randomData(count: diffSize, using: &rng),
                chaff: randomData(count: chaffSize, using: &rng)
            )
            let encoded = instruction.encode()
            let decoded = try TransportInstruction(decode: encoded)
            XCTAssertEqual(decoded, instruction)
        }
    }

    func testTransportInstructionSkipsUnknownFields() throws {
        var writer = ProtoWriter()
        writer.writeKey(fieldNumber: 1, wireType: 0)
        writer.writeVarint(2)
        writer.writeKey(fieldNumber: 99, wireType: 0)
        writer.writeVarint(12345)
        let diff = Data([0x01, 0x02, 0x03])
        writer.writeKey(fieldNumber: 6, wireType: 2)
        writer.writeLengthDelimited(diff)
        writer.writeKey(fieldNumber: 100, wireType: 2)
        writer.writeLengthDelimited(Data([0xAA, 0xBB]))

        let decoded = try TransportInstruction(decode: writer.data)
        XCTAssertEqual(decoded.protocolVersion, 2)
        XCTAssertEqual(decoded.diff, diff)
    }

    func testTransportInstructionLargePayloadRoundTrip() throws {
        let diff = Data(repeating: 0xAB, count: 128 * 1024)
        let chaff = Data(repeating: 0xCD, count: 128 * 1024)
        let instruction = TransportInstruction(
            protocolVersion: 2,
            oldNum: 1,
            newNum: 2,
            ackNum: 3,
            throwawayNum: 4,
            diff: diff,
            chaff: chaff
        )
        let decoded = try TransportInstruction(decode: instruction.encode())
        XCTAssertEqual(decoded, instruction)
    }

    func testUserMessageRoundTripMergesKeystrokes() throws {
        let events: [UserEvent] = [
            .keystroke(Data("ls".utf8)),
            .keystroke(Data(" -la".utf8)),
            .resize(cols: 80, rows: 24),
            .keystroke(Data("pwd".utf8))
        ]

        let encoded = UserMessageCodec.encode(events: events)
        let decoded = try UserMessageCodec.decode(data: encoded)

        let expected: [UserEvent] = [
            .keystroke(Data("ls -la".utf8)),
            .resize(cols: 80, rows: 24),
            .keystroke(Data("pwd".utf8))
        ]
        XCTAssertEqual(decoded, expected)
    }

    func testUserMessageDecodeSkipsUnknownFields() throws {
        var keystrokeWriter = ProtoWriter()
        keystrokeWriter.writeKey(fieldNumber: 4, wireType: 2)
        keystrokeWriter.writeLengthDelimited(Data([0x41]))
        keystrokeWriter.writeKey(fieldNumber: 50, wireType: 0)
        keystrokeWriter.writeVarint(123)

        var instructionWriter = ProtoWriter()
        instructionWriter.writeKey(fieldNumber: 2, wireType: 2)
        instructionWriter.writeLengthDelimited(keystrokeWriter.data)
        instructionWriter.writeKey(fieldNumber: 99, wireType: 0)
        instructionWriter.writeVarint(456)

        var messageWriter = ProtoWriter()
        messageWriter.writeKey(fieldNumber: 1, wireType: 2)
        messageWriter.writeLengthDelimited(instructionWriter.data)
        messageWriter.writeKey(fieldNumber: 200, wireType: 2)
        messageWriter.writeLengthDelimited(Data([0x00]))

        let decoded = try UserMessageCodec.decode(data: messageWriter.data)
        XCTAssertEqual(decoded, [.keystroke(Data([0x41]))])
    }

    func testHostMessageDecodeEvents() throws {
        let hostBytes = Data("\u{1B}[31mHi\u{1B}[0m".utf8)
        let hostInstruction = encodeHostBytesInstruction(hostBytes)
        let resizeInstruction = encodeResizeInstruction(cols: 100, rows: 40)
        let echoAckInstruction = encodeEchoAckInstruction(9001)

        var messageWriter = ProtoWriter()
        for instruction in [hostInstruction, resizeInstruction, echoAckInstruction] {
            messageWriter.writeKey(fieldNumber: 1, wireType: 2)
            messageWriter.writeLengthDelimited(instruction)
        }

        let decoded = try HostMessageCodec.decode(data: messageWriter.data)
        let expected: [HostEvent] = [
            .hostBytes(hostBytes),
            .resize(cols: 100, rows: 40),
            .echoAck(9001)
        ]
        XCTAssertEqual(decoded, expected)
    }

    private func randomData(count: Int, using rng: inout SystemRandomNumberGenerator) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for _ in 0..<count {
            bytes.append(UInt8.random(in: 0...UInt8.max, using: &rng))
        }
        return Data(bytes)
    }

    private func encodeHostBytesInstruction(_ bytes: Data) -> Data {
        var hostBytesWriter = ProtoWriter()
        hostBytesWriter.writeKey(fieldNumber: 4, wireType: 2)
        hostBytesWriter.writeLengthDelimited(bytes)

        var instructionWriter = ProtoWriter()
        instructionWriter.writeKey(fieldNumber: 2, wireType: 2)
        instructionWriter.writeLengthDelimited(hostBytesWriter.data)
        return instructionWriter.data
    }

    private func encodeResizeInstruction(cols: Int, rows: Int) -> Data {
        var resizeWriter = ProtoWriter()
        resizeWriter.writeKey(fieldNumber: 5, wireType: 0)
        resizeWriter.writeVarint(UInt64(cols))
        resizeWriter.writeKey(fieldNumber: 6, wireType: 0)
        resizeWriter.writeVarint(UInt64(rows))

        var instructionWriter = ProtoWriter()
        instructionWriter.writeKey(fieldNumber: 3, wireType: 2)
        instructionWriter.writeLengthDelimited(resizeWriter.data)
        return instructionWriter.data
    }

    private func encodeEchoAckInstruction(_ value: UInt64) -> Data {
        var echoWriter = ProtoWriter()
        echoWriter.writeKey(fieldNumber: 8, wireType: 0)
        echoWriter.writeVarint(value)

        var instructionWriter = ProtoWriter()
        instructionWriter.writeKey(fieldNumber: 7, wireType: 2)
        instructionWriter.writeLengthDelimited(echoWriter.data)
        return instructionWriter.data
    }
}
