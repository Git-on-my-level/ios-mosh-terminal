import Foundation
import Darwin

protocol DatagramSocket: AnyObject, Sendable {
    func send(_ data: Data) throws
    func receive() async throws -> Data
    func close()
}

protocol DatagramSocketPortProviding: AnyObject {
    var localPort: UInt16 { get }
}

enum DatagramSocketError: Error, LocalizedError, Equatable {
    case resolutionFailed(host: String)
    case socketCreationFailed(errno: Int32)
    case bindFailed(port: UInt16?, errno: Int32)
    case sendFailed(errno: Int32)
    case receiveFailed(errno: Int32)
    case closed

    var errorDescription: String? {
        switch self {
        case .resolutionFailed(let host):
            return "Unable to resolve host: \(host)."
        case .socketCreationFailed(let errno):
            return "Unable to create socket (errno \(errno))."
        case .bindFailed(let port, let errno):
            if let port {
                return "Unable to bind socket to port \(port) (errno \(errno))."
            }
            return "Unable to bind socket (errno \(errno))."
        case .sendFailed(let errno):
            return "Unable to send UDP datagram (errno \(errno))."
        case .receiveFailed(let errno):
            return "Unable to receive UDP datagram (errno \(errno))."
        case .closed:
            return "Socket is closed."
        }
    }
}

struct DatagramSocketLogEvent: Equatable {
    enum Kind: Equatable {
        case opened(localPort: UInt16)
        case hop(from: UInt16, to: UInt16)
        case sendError(errno: Int32)
        case closed(localPort: UInt16)
    }

    let kind: Kind
}

final class BSDDatagramSocket: DatagramSocket, DatagramSocketPortProviding, @unchecked Sendable {
    struct Configuration {
        enum LocalPortStrategy: Equatable {
            case ephemeral
            case random(range: ClosedRange<UInt16>)
        }

        var localPortStrategy: LocalPortStrategy = .random(range: 60001...60999)
        var maxDatagramSize: Int = 65535
        var queue: DispatchQueue = DispatchQueue(label: "DatagramSocket.read")
    }

    private let fileDescriptor: Int32
    private let remoteAddress: sockaddr_storage
    private let remoteAddressLength: socklen_t
    private let maxDatagramSize: Int
    private let queue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let stream: AsyncThrowingStream<Data, Error>
    private var iterator: AsyncThrowingStream<Data, Error>.Iterator
    private let stateLock = NSLock()
    private var isClosed = false

    let localPort: UInt16

    init(host: String, port: UInt16, configuration: Configuration = Configuration()) throws {
        self.maxDatagramSize = configuration.maxDatagramSize
        self.queue = configuration.queue

        var createdSocket: Int32 = -1
        var selectedRemote = sockaddr_storage()
        var selectedRemoteLen: socklen_t = 0
        var boundPort: UInt16 = 0

        if let numeric = Self.resolveNumeric(host: host, port: port) {
            let socketFD = socket(numeric.family, SOCK_DGRAM, IPPROTO_UDP)
            if socketFD >= 0, Self.configureSocket(socketFD) {
                boundPort = try Self.bindSocket(
                    socketFD,
                    family: numeric.family,
                    strategy: configuration.localPortStrategy
                )
                createdSocket = socketFD
                selectedRemote = numeric.address
                selectedRemoteLen = numeric.length
            } else if socketFD >= 0 {
                Darwin.close(socketFD)
            }
        } else {
            guard let addressInfo = Self.resolve(host: host, port: port) else {
                throw DatagramSocketError.resolutionFailed(host: host)
            }

            var current = addressInfo
            while true {
                let ai = current.pointee
                let socketFD = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
                if socketFD >= 0 {
                    if Self.configureSocket(socketFD) {
                        do {
                            boundPort = try Self.bindSocket(
                                socketFD,
                                family: ai.ai_family,
                                strategy: configuration.localPortStrategy
                            )
                            createdSocket = socketFD
                            memcpy(&selectedRemote, ai.ai_addr, Int(ai.ai_addrlen))
                            selectedRemoteLen = ai.ai_addrlen
                            break
                        } catch {
                            Darwin.close(socketFD)
                        }
                    } else {
                        Darwin.close(socketFD)
                    }
                }
                if let next = ai.ai_next {
                    current = next
                } else {
                    break
                }
            }

            freeaddrinfo(addressInfo)
        }

        guard createdSocket >= 0 else {
            throw DatagramSocketError.socketCreationFailed(errno: errno)
        }

        self.fileDescriptor = createdSocket
        self.remoteAddress = selectedRemote
        self.remoteAddressLength = selectedRemoteLen
        self.localPort = boundPort

        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let stream = AsyncThrowingStream<Data, Error> { continuation = $0 }
        self.stream = stream
        self.iterator = stream.makeAsyncIterator()
        self.streamContinuation = continuation

        let source = DispatchSource.makeReadSource(fileDescriptor: createdSocket, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleReadEvent()
        }
        source.setCancelHandler { [fd = createdSocket] in
            Darwin.close(fd)
        }
        self.readSource = source
        source.resume()
    }

    deinit {
        close()
    }

    func send(_ data: Data) throws {
        stateLock.lock()
        let closed = isClosed
        stateLock.unlock()
        if closed {
            throw DatagramSocketError.closed
        }

        let result: Int = data.withUnsafeBytes { rawBuffer in
            let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            return sendto(
                fileDescriptor,
                baseAddress,
                rawBuffer.count,
                0,
                withUnsafePointer(to: remoteAddress) { pointer in
                    UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self)
                },
                remoteAddressLength
            )
        }
        if result < 0 {
            throw DatagramSocketError.sendFailed(errno: errno)
        }
    }

    func receive() async throws -> Data {
        stateLock.lock()
        let closed = isClosed
        stateLock.unlock()
        if closed {
            throw DatagramSocketError.closed
        }
        guard let next = try await iterator.next() else {
            throw DatagramSocketError.closed
        }
        return next
    }

    func close() {
        stateLock.lock()
        if isClosed {
            stateLock.unlock()
            return
        }
        isClosed = true
        stateLock.unlock()
        readSource?.cancel()
        readSource = nil
        streamContinuation?.finish()
        streamContinuation = nil
    }

    private func handleReadEvent() {
        guard let continuation = streamContinuation else { return }
        var buffer = [UInt8](repeating: 0, count: maxDatagramSize)
        while true {
            var addrStorage = sockaddr_storage()
            var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let received = buffer.withUnsafeMutableBytes { rawBuffer in
                withUnsafeMutablePointer(to: &addrStorage) { addrPointer in
                    recvfrom(
                        fileDescriptor,
                        rawBuffer.baseAddress,
                        rawBuffer.count,
                        0,
                        UnsafeMutableRawPointer(addrPointer).assumingMemoryBound(to: sockaddr.self),
                        &addrLen
                    )
                }
            }
            if received > 0 {
                continuation.yield(Data(buffer.prefix(Int(received))))
            } else if received == 0 {
                break
            } else {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                continuation.finish(throwing: DatagramSocketError.receiveFailed(errno: errno))
                close()
                break
            }
        }
    }

    private static func configureSocket(_ socketFD: Int32) -> Bool {
        var value: Int32 = 1
        if setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size)) != 0 {
            return false
        }
        let flags = fcntl(socketFD, F_GETFL)
        if flags < 0 {
            return false
        }
        if fcntl(socketFD, F_SETFL, flags | O_NONBLOCK) < 0 {
            return false
        }
        return true
    }

    private static func bindSocket(
        _ socketFD: Int32,
        family: Int32,
        strategy: Configuration.LocalPortStrategy
    ) throws -> UInt16 {
        let port: UInt16
        switch strategy {
        case .ephemeral:
            port = 0
        case .random(let range):
            port = UInt16.random(in: range)
        }

        let didBind: Bool
        if family == AF_INET {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
            didBind = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        } else {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = port.bigEndian
            addr.sin6_addr = in6addr_any
            didBind = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
                }
            }
        }

        if !didBind {
            let bindErrno = errno
            if case .random(let range) = strategy {
                do {
                    return try bindWithRandomPorts(socketFD, family: family, range: range)
                } catch {
                    return try bindEphemeral(socketFD, family: family)
                }
            }
            throw DatagramSocketError.bindFailed(port: port == 0 ? nil : port, errno: bindErrno)
        }

        return resolveBoundPort(socketFD)
    }

    private static func bindWithRandomPorts(
        _ socketFD: Int32,
        family: Int32,
        range: ClosedRange<UInt16>
    ) throws -> UInt16 {
        let attempts = 16
        for _ in 0..<attempts {
            let port = UInt16.random(in: range)
            let didBind: Bool
            if family == AF_INET {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
                didBind = withUnsafePointer(to: &addr) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                    }
                }
            } else {
                var addr = sockaddr_in6()
                addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                addr.sin6_family = sa_family_t(AF_INET6)
                addr.sin6_port = port.bigEndian
                addr.sin6_addr = in6addr_any
                didBind = withUnsafePointer(to: &addr) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
                    }
                }
            }
            if didBind {
                return resolveBoundPort(socketFD)
            }
        }
        throw DatagramSocketError.bindFailed(port: nil, errno: errno)
    }

    private static func bindEphemeral(_ socketFD: Int32, family: Int32) throws -> UInt16 {
        let didBind: Bool
        if family == AF_INET {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = 0
            addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
            didBind = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        } else {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = 0
            addr.sin6_addr = in6addr_any
            didBind = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
                }
            }
        }
        if !didBind {
            throw DatagramSocketError.bindFailed(port: nil, errno: errno)
        }
        return resolveBoundPort(socketFD)
    }

    private static func resolveBoundPort(_ socketFD: Int32) -> UInt16 {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        guard result == 0 else { return 0 }
        if storage.ss_family == sa_family_t(AF_INET) {
            return withUnsafePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { bound in
                    UInt16(bigEndian: bound.pointee.sin_port)
                }
            }
        }
        if storage.ss_family == sa_family_t(AF_INET6) {
            return withUnsafePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { bound in
                    UInt16(bigEndian: bound.pointee.sin6_port)
                }
            }
        }
        return 0
    }

    private static func resolve(host: String, port: UInt16) -> UnsafeMutablePointer<addrinfo>? {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP
        hints.ai_family = AF_UNSPEC
        hints.ai_flags = 0

        var result: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let status = getaddrinfo(host, portString, &hints, &result)
        if status != 0 {
            return nil
        }
        return result
    }

    private static func resolveNumeric(host: String, port: UInt16) -> (address: sockaddr_storage, length: socklen_t, family: Int32)? {
        var storage = sockaddr_storage()
        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr = ipv4
            memcpy(&storage, &addr, MemoryLayout<sockaddr_in>.size)
            return (storage, socklen_t(MemoryLayout<sockaddr_in>.size), AF_INET)
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = port.bigEndian
            addr.sin6_addr = ipv6
            memcpy(&storage, &addr, MemoryLayout<sockaddr_in6>.size)
            return (storage, socklen_t(MemoryLayout<sockaddr_in6>.size), AF_INET6)
        }
        return nil
    }
}
