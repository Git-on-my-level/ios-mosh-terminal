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

    func testFragmentEncodeDecodeRoundTrip() throws {
        let fragment = Fragment(id: 42, number: 7, isFinal: true, body: Data([0xAA, 0xBB]))
        let encoded = fragment.encode()
        let decoded = try Fragment(decode: encoded)
        XCTAssertEqual(decoded, fragment)
    }

    func testFragmentAssemblyInOrder() throws {
        let payload = Data("hello-world".utf8)
        let fragments = Fragmenter.makeFragments(instructionBytes: payload, mtu: 4, id: 1)
        let assembly = FragmentAssembly()
        var completed = false
        for fragment in fragments {
            completed = assembly.add(fragment)
        }
        XCTAssertTrue(completed)
        let reassembled = try assembly.assembledBytes()
        XCTAssertEqual(reassembled, payload)
    }

    func testFragmentAssemblyOutOfOrder() throws {
        let payload = Data("fragment-test".utf8)
        let fragments = Fragmenter.makeFragments(instructionBytes: payload, mtu: 5, id: 2)
        let assembly = FragmentAssembly()
        XCTAssertFalse(assembly.add(fragments[1]))
        XCTAssertFalse(assembly.add(fragments[0]))
        XCTAssertTrue(assembly.add(fragments[2]))
        let reassembled = try assembly.assembledBytes()
        XCTAssertEqual(reassembled, payload)
    }

    func testFragmentAssemblySwitchingIdsResets() throws {
        let first = Fragmenter.makeFragments(instructionBytes: Data("first".utf8), mtu: 3, id: 10)
        let secondPayload = Data("second-payload".utf8)
        let second = Fragmenter.makeFragments(instructionBytes: secondPayload, mtu: 4, id: 11)
        let assembly = FragmentAssembly()
        _ = assembly.add(first[0])
        for fragment in second {
            _ = assembly.add(fragment)
        }
        let reassembled = try assembly.assembledBytes()
        XCTAssertEqual(reassembled, secondPayload)
    }

    func testFragmentAssemblyDuplicateFragmentMatches() throws {
        let payload = Data("duplicate".utf8)
        let fragments = Fragmenter.makeFragments(instructionBytes: payload, mtu: 4, id: 3)
        let assembly = FragmentAssembly()
        XCTAssertFalse(assembly.add(fragments[0]))
        XCTAssertFalse(assembly.add(fragments[0]))
        for fragment in fragments.dropFirst() {
            _ = assembly.add(fragment)
        }
        let reassembled = try assembly.assembledBytes()
        XCTAssertEqual(reassembled, payload)
    }

    func testTransportFramingOutboundInboundRoundTrip() throws {
        let framing = TransportFraming(packetCodec: IdentityPacketCodec())
        let instruction = TransportInstruction(
            protocolVersion: 2,
            oldNum: 1,
            newNum: 2,
            ackNum: 3,
            throwawayNum: 4,
            diff: Data("ping".utf8),
            chaff: Data("chaff".utf8)
        )

        let datagrams = try framing.makeOutboundDatagrams(instruction: instruction, mtu: 1200)
        XCTAssertFalse(datagrams.isEmpty)

        var decoded: TransportInstruction?
        for (index, datagram) in datagrams.enumerated() {
            let result = try framing.processInboundDatagram(datagram)
            if index < datagrams.count - 1 {
                XCTAssertNil(result)
            } else {
                decoded = result
            }
        }

        XCTAssertEqual(decoded, instruction)
    }

    func testTransportFramingMultiFragmentReassembly() throws {
        let framing = TransportFraming(packetCodec: IdentityPacketCodec())
        var bytes = [UInt8](repeating: 0, count: 4096)
        for index in 0..<bytes.count {
            bytes[index] = UInt8(truncatingIfNeeded: index)
        }
        let instruction = TransportInstruction(
            protocolVersion: 2,
            diff: Data(bytes)
        )

        let datagrams = try framing.makeOutboundDatagrams(instruction: instruction, mtu: 200)
        XCTAssertGreaterThan(datagrams.count, 1)

        var decoded: TransportInstruction?
        for datagram in datagrams {
            decoded = try framing.processInboundDatagram(datagram) ?? decoded
        }
        XCTAssertEqual(decoded, instruction)
    }

    func testTransportFramingRejectsTruncatedDatagram() {
        let framing = TransportFraming(packetCodec: IdentityPacketCodec())
        let truncated = Data([0x01, 0x02, 0x03])
        XCTAssertThrowsError(try framing.processInboundDatagram(truncated)) { error in
            XCTAssertNotNil(error as? FragmentError)
        }
    }

    func testTransportFramingRejectsInvalidProtocolVersion() {
        let framing = TransportFraming(packetCodec: IdentityPacketCodec())
        let instruction = TransportInstruction(protocolVersion: 1, diff: Data([0x01]))
        XCTAssertThrowsError(try framing.makeOutboundDatagrams(instruction: instruction, mtu: 1200)) { error in
            XCTAssertEqual(error as? TransportFramingError, .invalidProtocolVersion(expected: 2, actual: 1))
        }
    }

    func testOCBSessionRoundTripSizes() throws {
        let key = [UInt8](0..<16)
        let session = try OCBSession(key16: key)
        let sizes = [0, 1, 15, 16, 31, 32, 1024]
        for (index, size) in sizes.enumerated() {
            let nonceVal = UInt64(100 + index)
            var bytes = [UInt8](repeating: 0, count: size)
            for offset in 0..<size {
                bytes[offset] = UInt8(truncatingIfNeeded: offset)
            }
            let plaintext = Data(bytes)
            let encrypted = try session.encrypt(nonceVal: nonceVal, plaintext: plaintext)
            let (decodedNonce, decodedPlaintext) = try session.decrypt(ciphertext: encrypted)
            XCTAssertEqual(decodedNonce, nonceVal)
            XCTAssertEqual(decodedPlaintext, plaintext)
        }
    }

    func testOCBSessionTamperFails() throws {
        let key = [UInt8](0..<16)
        let session = try OCBSession(key16: key)
        let plaintext = Data("tamper-test".utf8)
        let encrypted = try session.encrypt(nonceVal: 42, plaintext: plaintext)

        var tamperedCiphertext = encrypted
        tamperedCiphertext[8] ^= 0xFF
        XCTAssertThrowsError(try session.decrypt(ciphertext: tamperedCiphertext))

        var tamperedTag = encrypted
        tamperedTag[tamperedTag.count - 1] ^= 0x01
        XCTAssertThrowsError(try session.decrypt(ciphertext: tamperedTag))

        let truncated = Data(encrypted.prefix(7))
        XCTAssertThrowsError(try session.decrypt(ciphertext: truncated))
    }

    func testOCBSessionNonceFormatting() throws {
        let key = [UInt8](0..<16)
        let session = try OCBSession(key16: key)
        let nonceVal: UInt64 = 0x0102030405060708
        let encrypted = try session.encrypt(nonceVal: nonceVal, plaintext: Data())
        let noncePrefix = encrypted.prefix(8)
        XCTAssertEqual(noncePrefix, Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
    }

    func testOCBRFC7253Vector() throws {
        let key = bytesFromHex("000102030405060708090A0B0C0D0E0F")
        let nonce = bytesFromHex("BBAA99887766554433221103")
        let plaintext = bytesFromHex("0001020304050607")
        let expected = bytesFromHex("45DD69F8F5AAE72414054CD1F35D82760B2CD00D2F99BFA9")

        guard let ctx = ae_allocate(nil) else {
            XCTFail("Failed to allocate OCB context")
            return
        }
        defer {
            _ = ae_clear(ctx)
            ae_free(ctx)
        }

        let initResult = key.withUnsafeBytes { keyPtr in
            ae_init(ctx, keyPtr.baseAddress, Int32(key.count), 12, 16)
        }
        XCTAssertEqual(initResult, AE_SUCCESS)

        var ciphertext = [UInt8](repeating: 0, count: plaintext.count)
        var tag = [UInt8](repeating: 0, count: 16)
        let encryptResult = nonce.withUnsafeBytes { noncePtr in
            plaintext.withUnsafeBytes { ptPtr in
                ciphertext.withUnsafeMutableBytes { ctPtr in
                    tag.withUnsafeMutableBytes { tagPtr in
                        ae_encrypt(
                            ctx,
                            noncePtr.baseAddress,
                            ptPtr.baseAddress,
                            Int32(plaintext.count),
                            nil,
                            0,
                            ctPtr.baseAddress,
                            tagPtr.baseAddress,
                            AE_FINALIZE
                        )
                    }
                }
            }
        }
        XCTAssertEqual(Int(encryptResult), plaintext.count)
        XCTAssertEqual(Data(ciphertext + tag), Data(expected))
    }

    func testTransportReceiverAppliesInOrderDiffsAndAcks() throws {
        let sender = TransportSender()
        let applier = TestHostDiffApplier()
        let receiver = TransportReceiver(
            transportSender: sender,
            hostApplier: applier.asHostApplier()
        )

        let hostBytes = Data("hello".utf8)
        let diff = encodeHostMessageDiff([
            encodeHostBytesInstruction(hostBytes),
            encodeResizeInstruction(cols: 100, rows: 40)
        ])
        let instruction = TransportInstruction(
            protocolVersion: 2,
            oldNum: 0,
            newNum: 1,
            diff: diff
        )

        try receiver.process(instruction)

        XCTAssertEqual(receiver.remoteStateTracker.lastAppliedRemoteNum, 1)
        XCTAssertEqual(sender.ackNum, 1)
        XCTAssertEqual(applier.appliedEvents, [
            .hostBytes(hostBytes),
            .resize(cols: 100, rows: 40)
        ])
    }

    func testTransportReceiverIgnoresOutOfOrderDiffs() throws {
        let sender = TransportSender()
        let applier = TestHostDiffApplier()
        let receiver = TransportReceiver(
            transportSender: sender,
            hostApplier: applier.asHostApplier()
        )

        let diff = encodeHostMessageDiff([
            encodeHostBytesInstruction(Data([0x01]))
        ])
        let instruction = TransportInstruction(
            protocolVersion: 2,
            oldNum: 2,
            newNum: 3,
            diff: diff
        )

        try receiver.process(instruction)

        XCTAssertEqual(receiver.remoteStateTracker.lastAppliedRemoteNum, 0)
        XCTAssertEqual(sender.ackNum, 0)
        XCTAssertTrue(applier.appliedEvents.isEmpty)
    }

    func testTransportReceiverProcessesAckNum() throws {
        let sender = TransportSender()
        sender.setConnected(true, nowMillis: 0)

        sender.currentState.append(.keystroke(Data([0x41])))
        _ = sender.tick(nowMillis: 10)

        sender.currentState.append(.keystroke(Data([0x42])))
        _ = sender.tick(nowMillis: 40)

        XCTAssertEqual(sender.sentStates.map(\.num), [1, 2])

        let applier = TestHostDiffApplier()
        let receiver = TransportReceiver(
            transportSender: sender,
            hostApplier: applier.asHostApplier()
        )

        let instruction = TransportInstruction(
            protocolVersion: 2,
            ackNum: 1
        )

        try receiver.process(instruction)

        XCTAssertEqual(sender.sentStates.map(\.num), [2])
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

    private func encodeHostMessageDiff(_ instructions: [Data]) -> Data {
        var writer = ProtoWriter()
        for instruction in instructions {
            writer.writeKey(fieldNumber: 1, wireType: 2)
            writer.writeLengthDelimited(instruction)
        }
        return writer.data
    }

    private func bytesFromHex(_ hex: String) -> [UInt8] {
        let sanitized = hex.filter { !$0.isWhitespace }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(sanitized.count / 2)
        var index = sanitized.startIndex
        while index < sanitized.endIndex {
            let nextIndex = sanitized.index(index, offsetBy: 2)
            let byteString = sanitized[index..<nextIndex]
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return bytes
    }

    private struct IdentityPacketCodec: PacketCodec {
        func encode(payload: Data, direction: PacketDirection) throws -> Data {
            payload
        }

        func decode(datagram: Data, expectedDirection: PacketDirection) throws -> Data {
            datagram
        }
    }

    private final class TestHostDiffApplier {
        private(set) var appliedEvents: [HostEvent] = []

        func asHostApplier() -> HostDiffApplier {
            HostDiffApplier(
                onTerminalOutput: { [weak self] data in
                    self?.appliedEvents.append(.hostBytes(data))
                },
                onResize: { [weak self] cols, rows in
                    self?.appliedEvents.append(.resize(cols: cols, rows: rows))
                },
                onEchoAck: { [weak self] value in
                    self?.appliedEvents.append(.echoAck(value))
                }
            )
        }
    }
}
