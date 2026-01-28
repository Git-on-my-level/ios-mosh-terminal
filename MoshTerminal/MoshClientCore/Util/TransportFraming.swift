import Foundation

enum PacketDirection: Equatable {
    case toServer
    case toClient
}

protocol PacketCodec {
    func encode(payload: Data, direction: PacketDirection) throws -> Data
    func decode(datagram: Data, expectedDirection: PacketDirection) throws -> Data
}

enum TransportFramingError: Error, Equatable {
    case invalidProtocolVersion(expected: UInt32, actual: UInt32)
    case mtuTooSmall(minimum: Int, actual: Int)
}

final class TransportFraming {
    static let expectedProtocolVersion: UInt32 = 2
    static let defaultPacketOverheadBytes = 24

    private let packetCodec: PacketCodec
    private let fragmentAssembly: FragmentAssembly
    private let sequenceCounter: SequenceCounter
    private let maxDecompressedBytes: Int
    private let packetOverheadBytes: Int

    init(packetCodec: PacketCodec,
         fragmentAssembly: FragmentAssembly = FragmentAssembly(),
         sequenceCounter: SequenceCounter = SequenceCounter(),
         maxDecompressedBytes: Int = ZlibCodec.defaultMaxOutputBytes,
         packetOverheadBytes: Int = TransportFraming.defaultPacketOverheadBytes) {
        self.packetCodec = packetCodec
        self.fragmentAssembly = fragmentAssembly
        self.sequenceCounter = sequenceCounter
        self.maxDecompressedBytes = maxDecompressedBytes
        self.packetOverheadBytes = packetOverheadBytes
    }

    func makeOutboundDatagrams(instruction: TransportInstruction, mtu: Int) throws -> [Data] {
        try validateProtocolVersion(instruction.protocolVersion)

        let minimumDatagramMtu = packetOverheadBytes + Fragment.headerBytes + 1
        guard mtu >= minimumDatagramMtu else {
            throw TransportFramingError.mtuTooSmall(minimum: minimumDatagramMtu, actual: mtu)
        }

        let encoded = instruction.encode()
        let compressed = try ZlibCodec.compress(encoded)
        let fragmentBodyMtu = mtu - packetOverheadBytes - Fragment.headerBytes
        let fragmentId = sequenceCounter.next()
        let fragments = Fragmenter.makeFragments(instructionBytes: compressed, mtu: fragmentBodyMtu, id: fragmentId)

        return try fragments.map { fragment in
            let payload = fragment.encode()
            return try packetCodec.encode(payload: payload, direction: .toServer)
        }
    }

    func processInboundDatagram(_ datagram: Data) throws -> TransportInstruction? {
        let payload = try packetCodec.decode(datagram: datagram, expectedDirection: .toClient)
        let fragment = try Fragment(decode: payload)
        let isComplete = fragmentAssembly.add(fragment)
        guard isComplete else {
            return nil
        }

        let compressed = try fragmentAssembly.assembledBytes()
        let decompressed = try ZlibCodec.decompress(compressed, maxOutputBytes: maxDecompressedBytes)
        let instruction = try TransportInstruction(decode: decompressed)
        try validateProtocolVersion(instruction.protocolVersion)
        return instruction
    }

    private func validateProtocolVersion(_ actual: UInt32) throws {
        guard actual == Self.expectedProtocolVersion else {
            throw TransportFramingError.invalidProtocolVersion(expected: Self.expectedProtocolVersion, actual: actual)
        }
    }
}
