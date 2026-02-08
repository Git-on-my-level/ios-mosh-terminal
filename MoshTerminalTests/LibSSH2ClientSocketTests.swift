#if LIBSSH2_AVAILABLE
import XCTest
import Darwin
@testable import MoshTerminal

final class LibSSH2ClientSocketTests: XCTestCase {
    private final class FakeSocketSystemCalls: LibSSH2Client.SocketSystemCalls {
        var currentErrno: Int32 = 0
        var socketHandler: ((Int32, Int32, Int32) -> Int32)?
        var connectHandler: ((Int32, UnsafePointer<sockaddr>?, socklen_t) -> Int32)?
        var pollHandler: ((UnsafeMutablePointer<pollfd>?, nfds_t, Int32) -> Int32)?
        var getsockoptHandler: ((Int32, Int32, Int32, UnsafeMutableRawPointer?, UnsafeMutablePointer<socklen_t>?) -> Int32)?
        var fcntlHandler: ((Int32, Int32, Int32) -> Int32)?
        var closeHandler: ((Int32) -> Int32)?

        func socket(_ domain: Int32, _ type: Int32, _ proto: Int32) -> Int32 {
            socketHandler?(domain, type, proto) ?? -1
        }

        func connect(_ socket: Int32, _ address: UnsafePointer<sockaddr>?, _ addressLen: socklen_t) -> Int32 {
            connectHandler?(socket, address, addressLen) ?? -1
        }

        func poll(_ fds: UnsafeMutablePointer<pollfd>?, _ nfds: nfds_t, _ timeout: Int32) -> Int32 {
            pollHandler?(fds, nfds, timeout) ?? 0
        }

        func getsockopt(
            _ socket: Int32,
            _ level: Int32,
            _ optionName: Int32,
            _ optionValue: UnsafeMutableRawPointer?,
            _ optionLen: UnsafeMutablePointer<socklen_t>?
        ) -> Int32 {
            getsockoptHandler?(socket, level, optionName, optionValue, optionLen) ?? 0
        }

        func fcntl(_ socket: Int32, _ command: Int32, _ value: Int32) -> Int32 {
            fcntlHandler?(socket, command, value) ?? 0
        }

        func close(_ socket: Int32) -> Int32 {
            closeHandler?(socket) ?? 0
        }

        func strerror(_ errnum: Int32) -> UnsafePointer<Int8>? {
            Darwin.strerror(errnum)
        }
    }

    private func makeLoopbackAddress(port: Int) -> LibSSH2Client.ResolvedAddress {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let data = Data(bytes: &addr, count: MemoryLayout<sockaddr_in>.size)
        return LibSSH2Client.ResolvedAddress(
            family: AF_INET,
            socktype: SOCK_STREAM,
            proto: IPPROTO_TCP,
            addrData: data
        )
    }

    func testConnectTimeoutProducesConnectionFailed() {
        let fake = FakeSocketSystemCalls()
        fake.socketHandler = { _, _, _ in 42 }
        fake.fcntlHandler = { _, command, _ in
            if command == F_GETFL {
                return 0
            }
            return 0
        }
        fake.connectHandler = { _, _, _ in
            fake.currentErrno = EINPROGRESS
            return -1
        }
        fake.pollHandler = { _, _, _ in 0 }

        let client = LibSSH2Client(systemCalls: fake)
        let address = makeLoopbackAddress(port: 22)
        let deadline = DispatchTime.now().advanced(by: .seconds(1))

        XCTAssertThrowsError(try client.openSocket(resolvedAddresses: [address], deadline: deadline)) { error in
            XCTAssertEqual(error as? SSHClientError, .connectionFailed(message: "Connection timed out."))
        }
    }

    func testCancelDuringConnectThrowsCancelled() {
        let fake = FakeSocketSystemCalls()
        fake.socketHandler = { _, _, _ in 42 }
        fake.fcntlHandler = { _, command, _ in
            if command == F_GETFL {
                return 0
            }
            return 0
        }
        fake.connectHandler = { _, _, _ in
            fake.currentErrno = EINPROGRESS
            return -1
        }

        let client = LibSSH2Client(systemCalls: fake)
        let cancelSemaphore = DispatchSemaphore(value: 0)
        fake.pollHandler = { _, _, _ in
            Task {
                await client.cancel()
                cancelSemaphore.signal()
            }
            _ = cancelSemaphore.wait(timeout: .now() + 1)
            fake.currentErrno = EINTR
            return -1
        }

        let address = makeLoopbackAddress(port: 22)
        let deadline = DispatchTime.now().advanced(by: .seconds(1))

        XCTAssertThrowsError(try client.openSocket(resolvedAddresses: [address], deadline: deadline)) { error in
            XCTAssertEqual(error as? SSHClientError, .cancelled)
        }
    }

    func testRemainingTimeoutMillisecondsEdgeCases() {
        let fake = FakeSocketSystemCalls()
        let client = LibSSH2Client(systemCalls: fake)
        let now = DispatchTime(uptimeNanoseconds: 1_000_000_000)

        let pastDeadline = DispatchTime(uptimeNanoseconds: now.uptimeNanoseconds - 1)
        XCTAssertEqual(client.remainingTimeoutMilliseconds(until: pastDeadline, now: now), 0)

        let tinyFuture = DispatchTime(uptimeNanoseconds: now.uptimeNanoseconds + 500_000)
        XCTAssertEqual(client.remainingTimeoutMilliseconds(until: tinyFuture, now: now), 1)

        let largeMs = UInt64(Int32.max) + 1
        let hugeDeadline = DispatchTime(uptimeNanoseconds: now.uptimeNanoseconds + largeMs * 1_000_000)
        XCTAssertEqual(client.remainingTimeoutMilliseconds(until: hugeDeadline, now: now), Int32.max)
    }
}
#endif
