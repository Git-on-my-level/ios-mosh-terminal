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
}

private final class UDPEchoServer {
    let port: UInt16

    private let socketFD: Int32
    private let queue = DispatchQueue(label: "UDPEchoServer")
    private var source: DispatchSourceRead?

    init() throws {
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            throw DatagramSocketError.socketCreationFailed(errno: errno)
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let didBind = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard didBind else {
            let bindErrno = errno
            Darwin.close(socketFD)
            throw DatagramSocketError.bindFailed(port: nil, errno: bindErrno)
        }

        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        guard result == 0 else {
            let bindErrno = errno
            Darwin.close(socketFD)
            throw DatagramSocketError.bindFailed(port: nil, errno: bindErrno)
        }
        if storage.ss_family == sa_family_t(AF_INET) {
            port = withUnsafePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt16(bigEndian: $0.pointee.sin_port)
                }
            }
        } else {
            port = 0
        }

        let flags = fcntl(socketFD, F_GETFL)
        if flags >= 0 {
            _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: Int(socketFD), queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleRead()
        }
        source.setCancelHandler { [fd = socketFD] in
            Darwin.close(fd)
        }
        self.source = source
        source.resume()
    }

    func close() {
        source?.cancel()
        source = nil
    }

    private func handleRead() {
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
