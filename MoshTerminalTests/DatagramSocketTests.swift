import Foundation
import Darwin
import XCTest
@testable import MoshTerminal

final class DatagramSocketTests: XCTestCase {
    func testBSDDatagramSocketEchoesFromLocalServer() async throws {
        let server = try UDPEchoServer()
        defer { server.close() }

        let configuration = BSDDatagramSocket.Configuration(localPortStrategy: .ephemeral)
        let socket = try BSDDatagramSocket(host: "127.0.0.1", port: server.port, configuration: configuration)
        defer { socket.close() }

        let payload = Data("hello".utf8)
        try socket.send(payload)
        let echoed = try await socket.receive()

        XCTAssertEqual(echoed, payload)
    }

    func testRoamingDatagramSocketThrowsWhenNoSocketsAvailable() throws {
        let mockSocket = MockDatagramSocket()
        var config = RoamingDatagramSocket.Configuration()
        config.enablePortHopping = false
        config.socketFactory = { _, _ in mockSocket }

        let socket = try RoamingDatagramSocket(host: "127.0.0.1", port: 12345, configuration: config)
        defer { socket.close() }

        mockSocket.close()

        let expectation = XCTestExpectation(description: "Receive should complete with error")
        Task {
            do {
                _ = try await socket.receive()
                XCTFail("Expected error when no sockets available")
            } catch {
                if case DatagramSocketError.closed = error {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected DatagramSocketError.closed, got: \(error)")
                }
            }
        }

        wait(for: [expectation], timeout: 1.0)

        let payload = Data("test".utf8)
        do {
            try socket.send(payload)
            XCTFail("Expected error when trying to send with no sockets")
        } catch {
            if case DatagramSocketError.closed = error {
            } else {
                XCTFail("Expected DatagramSocketError.closed, got: \(error)")
            }
        }
    }
}

final class MockDatagramSocket: DatagramSocket, @unchecked Sendable {
    private let stateLock = NSLock()
    private var _isClosed = false
    private var _continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let _stream: AsyncThrowingStream<Data, Error>

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let stream = AsyncThrowingStream<Data, Error> { continuation = $0 }
        _stream = stream
        _continuation = continuation
    }

    func send(_ data: Data) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        if _isClosed {
            throw DatagramSocketError.closed
        }
    }

    func receive() async throws -> Data {
        var iterator = _stream.makeAsyncIterator()
        guard let data = try await iterator.next() else {
            throw DatagramSocketError.closed
        }
        return data
    }

    func close() {
        stateLock.lock()
        defer { stateLock.unlock() }
        _isClosed = true
        _continuation?.finish(throwing: DatagramSocketError.closed)
        _continuation = nil
    }
}

private final class UDPEchoServer {
    let port: UInt16

    private let socketFD: Int32
    private let queue = DispatchQueue(label: "UDPEchoServer")
    private var source: DispatchSourceRead? = nil

    init() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw DatagramSocketError.socketCreationFailed(errno: errno)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let didBind = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard didBind else {
            let bindErrno = errno
            Darwin.close(fd)
            throw DatagramSocketError.bindFailed(port: nil, errno: bindErrno)
        }

        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard result == 0 else {
            let bindErrno = errno
            Darwin.close(fd)
            throw DatagramSocketError.bindFailed(port: nil, errno: bindErrno)
        }
        let resolvedPort: UInt16
        if storage.ss_family == sa_family_t(AF_INET) {
            resolvedPort = withUnsafePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt16(bigEndian: $0.pointee.sin_port)
                }
            }
        } else {
            resolvedPort = 0
        }

        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        socketFD = fd
        port = resolvedPort
        source = Self.makeSource(fd: fd, queue: queue)
    }

    func close() {
        source?.cancel()
        source = nil
    }

    private static func makeSource(fd: Int32, queue: DispatchQueue) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            handleRead(socketFD: fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        return source
    }

    private static func handleRead(socketFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            var addrStorage = sockaddr_storage()
            var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let received = buffer.withUnsafeMutableBytes { rawBuffer in
                withUnsafeMutablePointer(to: &addrStorage) { addrPointer in
                    recvfrom(
                        socketFD,
                        rawBuffer.baseAddress,
                        rawBuffer.count,
                        0,
                        UnsafeMutableRawPointer(addrPointer).assumingMemoryBound(to: sockaddr.self),
                        &addrLen
                    )
                }
            }
            if received > 0 {
                let data = Data(buffer.prefix(Int(received)))
                data.withUnsafeBytes { rawBuffer in
                    _ = sendto(
                        socketFD,
                        rawBuffer.baseAddress,
                        rawBuffer.count,
                        0,
                        withUnsafePointer(to: &addrStorage) { pointer in
                            UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self)
                        },
                        addrLen
                    )
                }
            } else {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                break
            }
        }
    }
}
