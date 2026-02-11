import Foundation
import XCTest
@testable import MoshClientCore
@testable import MoshTerminal

final class MoshRuntimeKeepaliveTests: XCTestCase {
    func testRuntimeKeepsAliveDuringIdle() async throws {
        let key = "AAAAAAAAAAAAAAAAAAAAAA"
        let sessionKey = try SessionKey.decode(key)
        let server = try MockMoshServer(sessionKey: sessionKey)
        let socket = MockMoshDatagramSocket(server: server)

        var config = MoshRuntime.Configuration()
        config.socketFactory = { _, _ in socket }
        config.idleTickSleepMillis = 10
        config.keepaliveIntervalMillis = 50
        config.livenessPolicy.inboundSilenceMillis = 200
        config.livenessPolicy.idleGraceMillis = 0

        let runtime = MoshRuntime(configuration: config)
        let connected = expectation(description: "connected")
        let disconnected = expectation(description: "disconnected")
        disconnected.isInverted = true
        let failed = expectation(description: "failed")
        failed.isInverted = true

        await runtime.setHandlers(onOutput: nil, onRemoteResize: nil, onEvent: { event in
            switch event {
            case .connected:
                connected.fulfill()
            case .disconnected:
                disconnected.fulfill()
            case .failed:
                failed.fulfill()
            }
        }, onEchoAck: nil)

        try await runtime.start(
            serverHost: "127.0.0.1",
            udpPort: 60000,
            key: key,
            initialSize: TerminalSize(cols: 80, rows: 24)
        )

        let connectedResult = await XCTWaiter().fulfillment(of: [connected], timeout: 1.0)
        XCTAssertEqual(connectedResult, .completed)

        let idleResult = await XCTWaiter().fulfillment(of: [disconnected, failed], timeout: 0.5)
        XCTAssertEqual(idleResult, .completed)

        await runtime.stop()
    }
}

private final class MockMoshDatagramSocket: DatagramSocket, @unchecked Sendable {
    private let stateLock = NSLock()
    private var isClosed = false
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let stream: AsyncThrowingStream<Data, Error>
    private var iterator: AsyncThrowingStream<Data, Error>.Iterator
    private let server: MockMoshServer

    init(server: MockMoshServer) {
        self.server = server
        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let stream = AsyncThrowingStream<Data, Error> { continuation = $0 }
        self.stream = stream
        self.iterator = stream.makeAsyncIterator()
        self.continuation = continuation
    }

    func send(_ data: Data) throws {
        stateLock.lock()
        let closed = isClosed
        stateLock.unlock()
        if closed {
            throw DatagramSocketError.closed
        }

        let responses = server.handleInbound(data)
        for response in responses {
            continuation?.yield(response)
        }
    }

    func receive() async throws -> Data {
        guard let data = try await iterator.next() else {
            throw DatagramSocketError.closed
        }
        return data
    }

    func close() {
        stateLock.lock()
        if isClosed {
            stateLock.unlock()
            return
        }
        isClosed = true
        stateLock.unlock()
        continuation?.finish(throwing: DatagramSocketError.closed)
        continuation = nil
    }
}

private final class MockMoshServer {
    private let framing: MockServerFraming
    private let mtu: Int

    init(sessionKey: [UInt8], mtu: Int = 1400) throws {
        let ocbSession = try OCBSession(key16: sessionKey)
        let packetCodec = OCBPacketCodec(session: ocbSession)
        framing = MockServerFraming(packetCodec: packetCodec)
        self.mtu = mtu
    }

    func handleInbound(_ datagram: Data) -> [Data] {
        do {
            guard let instruction = try framing.processInboundDatagram(datagram) else {
                return []
            }
            var response = TransportInstruction(protocolVersion: 2)
            if instruction.newNum != 0 {
                response.ackNum = instruction.newNum
            } else {
                response.ackNum = instruction.ackNum
            }
            return try framing.makeOutboundDatagrams(instruction: response, mtu: mtu)
        } catch {
            return []
        }
    }
}

private struct MockServerFraming {
    private let packetCodec: PacketCodec
    private let fragmentAssembly: FragmentAssembly
    private let sequenceCounter: SequenceCounter
    private let maxDecompressedBytes: Int
    private let packetOverheadBytes: Int

    init(
        packetCodec: PacketCodec,
        fragmentAssembly: FragmentAssembly = FragmentAssembly(),
        sequenceCounter: SequenceCounter = SequenceCounter(),
        maxDecompressedBytes: Int = ZlibCodec.defaultMaxOutputBytes,
        packetOverheadBytes: Int = TransportFraming.defaultPacketOverheadBytes
    ) {
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
            return try packetCodec.encode(payload: payload, direction: .toClient)
        }
    }

    func processInboundDatagram(_ datagram: Data) throws -> TransportInstruction? {
        let payload = try packetCodec.decode(datagram: datagram, expectedDirection: .toServer)
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
        guard actual == TransportFraming.expectedProtocolVersion else {
            throw TransportFramingError.invalidProtocolVersion(
                expected: TransportFraming.expectedProtocolVersion,
                actual: actual
            )
        }
    }
}
