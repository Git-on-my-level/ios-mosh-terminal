import Foundation

public enum PacketCodecError: Error, Equatable {
    case invalidDirection(expected: PacketDirection, actual: PacketDirection)
    case payloadTooShort
    case sequenceOverflow
}

public final class OCBPacketCodec: PacketCodec {
    private let session: OCBSession
    private let sendCounter: SequenceCounter
    private let lock = NSLock()
    private var lastReceivedTimestamp: UInt16 = 0

    public init(session: OCBSession, sendCounter: SequenceCounter = SequenceCounter()) {
        self.session = session
        self.sendCounter = sendCounter
    }

    public func encode(payload: Data, direction: PacketDirection) throws -> Data {
        let timestamp = Clock.timestamp16()
        let timestampReply = lastReceivedTimestampValue()
        var plaintext = Data()
        plaintext.reserveCapacity(4 + payload.count)
        plaintext.append(contentsOf: [
            UInt8(truncatingIfNeeded: timestamp >> 8),
            UInt8(truncatingIfNeeded: timestamp),
            UInt8(truncatingIfNeeded: timestampReply >> 8),
            UInt8(truncatingIfNeeded: timestampReply)
        ])
        plaintext.append(payload)

        let nonceVal = try nextNonceVal(direction: direction)
        return try session.encrypt(nonceVal: nonceVal, plaintext: plaintext)
    }

    public func decode(datagram: Data, expectedDirection: PacketDirection) throws -> Data {
        let (nonceVal, plaintext) = try session.decrypt(ciphertext: datagram)
        let actualDirection = direction(for: nonceVal)
        guard actualDirection == expectedDirection else {
            throw PacketCodecError.invalidDirection(expected: expectedDirection, actual: actualDirection)
        }
        guard plaintext.count >= 4 else {
            throw PacketCodecError.payloadTooShort
        }

        let bytes = [UInt8](plaintext)
        let timestamp = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        storeLastReceivedTimestamp(timestamp)
        return Data(bytes[4...])
    }

    private func nextNonceVal(direction: PacketDirection) throws -> UInt64 {
        let sequence = sendCounter.next()
        if (sequence & (1 << 63)) != 0 {
            throw PacketCodecError.sequenceOverflow
        }
        let directionBit: UInt64 = direction == .toClient ? (1 << 63) : 0
        return directionBit | sequence
    }

    private func direction(for nonceVal: UInt64) -> PacketDirection {
        let isToClient = (nonceVal & (1 << 63)) != 0
        return isToClient ? .toClient : .toServer
    }

    private func storeLastReceivedTimestamp(_ value: UInt16) {
        lock.lock()
        lastReceivedTimestamp = value
        lock.unlock()
    }

    private func lastReceivedTimestampValue() -> UInt16 {
        lock.lock()
        let value = lastReceivedTimestamp
        lock.unlock()
        return value
    }
}
