import XCTest
@testable import MoshClientCore
@testable import MoshTerminal

final class PacketCodecTests: XCTestCase {
    func testOCBPacketCodecEncodeDecodeRoundTrip() throws {
        let key = [UInt8](0..<16)
        let session = try OCBSession(key16: key)
        let codec = OCBPacketCodec(session: session)
        let payload = Data("hello".utf8)

        let datagram = try codec.encode(payload: payload, direction: .toServer)
        let decoded = try codec.decode(datagram: datagram, expectedDirection: .toServer)

        XCTAssertEqual(decoded, payload)
    }

    func testOCBPacketCodecRejectsWrongDirection() throws {
        let key = [UInt8](0..<16)
        let session = try OCBSession(key16: key)
        let codec = OCBPacketCodec(session: session)
        let payload = Data("direction".utf8)

        let datagram = try codec.encode(payload: payload, direction: .toClient)
        XCTAssertThrowsError(try codec.decode(datagram: datagram, expectedDirection: .toServer)) { error in
            XCTAssertEqual(error as? PacketCodecError, .invalidDirection(expected: .toServer, actual: .toClient))
        }
    }

    func testOCBPacketCodecTracksTimestampReply() throws {
        let key = [UInt8](0..<16)
        let session = try OCBSession(key16: key)
        let codec = OCBPacketCodec(session: session)
        let timestamp: UInt16 = 0x1234
        let payload = Data("incoming".utf8)
        var plaintext = Data([0x12, 0x34, 0x00, 0x00])
        plaintext.append(payload)
        let nonceVal = (UInt64(1) << 63) | 7
        let datagram = try session.encrypt(nonceVal: nonceVal, plaintext: plaintext)

        let decoded = try codec.decode(datagram: datagram, expectedDirection: .toClient)
        XCTAssertEqual(decoded, payload)

        let outbound = try codec.encode(payload: Data("ping".utf8), direction: .toServer)
        let (_, decrypted) = try session.decrypt(ciphertext: outbound)
        let reply = (UInt16(decrypted[2]) << 8) | UInt16(decrypted[3])
        XCTAssertEqual(reply, timestamp)
    }

    func testOCBPacketCodecRejectsTooShortPayload() throws {
        let key = [UInt8](0..<16)
        let session = try OCBSession(key16: key)
        let codec = OCBPacketCodec(session: session)
        let plaintext = Data([0x01, 0x02, 0x03])
        let nonceVal = (UInt64(1) << 63) | 1
        let datagram = try session.encrypt(nonceVal: nonceVal, plaintext: plaintext)

        XCTAssertThrowsError(try codec.decode(datagram: datagram, expectedDirection: .toClient)) { error in
            XCTAssertEqual(error as? PacketCodecError, .payloadTooShort)
        }
    }
}
