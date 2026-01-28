import Foundation

final class RoamingDatagramSocket: DatagramSocket, @unchecked Sendable {
    struct Configuration {
        var enablePortHopping: Bool = true
        var hopInterval: TimeInterval = 10
        var hopFailureWindow: TimeInterval = 10
        var staleSocketTTL: TimeInterval = 60
        var maxSockets: Int = 10
        var now: () -> Date = Date.init
        var enableLogging: Bool = false
        var logHandler: (DatagramSocketLogEvent) -> Void = { _ in }
        var socketFactory: (String, UInt16) throws -> DatagramSocket = { try BSDDatagramSocket(host: $0, port: $1) }
    }

    private struct Entry {
        let id: UUID
        let socket: DatagramSocket
        let openedAt: Date
        let localPort: UInt16?
        var receiverTask: Task<Void, Never>?
    }

    private let configuration: Configuration
    private let host: String
    private let port: UInt16
    private let stateLock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var currentSocketId: UUID?
    private var lastPortChoice: Date
    private var lastRoundtripSuccess: Date
    private var isClosed = false
    private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let stream: AsyncThrowingStream<Data, Error>
    private var iterator: AsyncThrowingStream<Data, Error>.Iterator

    init(host: String, port: UInt16, configuration: Configuration = Configuration()) throws {
        self.configuration = configuration
        self.host = host
        self.port = port
        let now = configuration.now()
        self.lastPortChoice = now
        self.lastRoundtripSuccess = now

        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let stream = AsyncThrowingStream<Data, Error> { continuation = $0 }
        self.stream = stream
        self.iterator = stream.makeAsyncIterator()
        self.streamContinuation = continuation

        let entry = try Self.makeEntry(
            host: host,
            port: port,
            configuration: configuration,
            openedAt: now
        )
        addEntry(entry, setCurrent: true, logEvent: entry.localPort.map { .opened(localPort: $0) })
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
        maybeHop()
        let socket = currentSocket()
        do {
            try socket.send(data)
        } catch {
            if configuration.enableLogging, let socketError = error as? DatagramSocketError {
                if case .sendFailed(let errno) = socketError {
                    configuration.logHandler(DatagramSocketLogEvent(kind: .sendError(errno: errno)))
                }
            }
            throw error
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
        let entriesToClose = entries.values
        entries.removeAll()
        currentSocketId = nil
        stateLock.unlock()

        for entry in entriesToClose {
            entry.receiverTask?.cancel()
            entry.socket.close()
            if configuration.enableLogging, let port = entry.localPort {
                configuration.logHandler(DatagramSocketLogEvent(kind: .closed(localPort: port)))
            }
        }
        streamContinuation?.finish()
        streamContinuation = nil
    }

    func recordRoundtripSuccess() {
        stateLock.lock()
        lastRoundtripSuccess = configuration.now()
        stateLock.unlock()
    }

    private func maybeHop() {
        guard configuration.enablePortHopping else { return }
        let now = configuration.now()
        stateLock.lock()
        let shouldHop = now.timeIntervalSince(lastPortChoice) > configuration.hopInterval
            && now.timeIntervalSince(lastRoundtripSuccess) > configuration.hopFailureWindow
        stateLock.unlock()
        guard shouldHop else { return }

        do {
            let entry = try Self.makeEntry(
                host: host,
                port: port,
                configuration: configuration,
                openedAt: now
            )
            if let toPort = entry.localPort, let fromPort = currentLocalPort() {
                addEntry(entry, setCurrent: true, logEvent: .hop(from: fromPort, to: toPort))
            } else {
                addEntry(entry, setCurrent: true, logEvent: nil)
            }
            pruneSockets(now: now)
        } catch {
            return
        }
    }

    private func pruneSockets(now: Date) {
        stateLock.lock()
        let currentId = currentSocketId
        var removable = entries.filter { now.timeIntervalSince($0.value.openedAt) > configuration.staleSocketTTL }
        var remaining = entries
        for (id, entry) in removable {
            if id != currentId {
                remaining.removeValue(forKey: id)
                entry.receiverTask?.cancel()
                entry.socket.close()
                if configuration.enableLogging, let port = entry.localPort {
                    configuration.logHandler(DatagramSocketLogEvent(kind: .closed(localPort: port)))
                }
            }
        }

        if remaining.count > configuration.maxSockets {
            let sorted = remaining.values.sorted { $0.openedAt < $1.openedAt }
            var toRemove = remaining.count - configuration.maxSockets
            for entry in sorted where toRemove > 0 {
                if entry.id == currentId { continue }
                remaining.removeValue(forKey: entry.id)
                entry.receiverTask?.cancel()
                entry.socket.close()
                if configuration.enableLogging, let port = entry.localPort {
                    configuration.logHandler(DatagramSocketLogEvent(kind: .closed(localPort: port)))
                }
                toRemove -= 1
            }
        }

        entries = remaining
        stateLock.unlock()
    }

    private func addEntry(_ entry: Entry, setCurrent: Bool, logEvent: DatagramSocketLogEvent.Kind?) {
        stateLock.lock()
        entries[entry.id] = entry
        if setCurrent {
            currentSocketId = entry.id
            lastPortChoice = entry.openedAt
        }
        stateLock.unlock()

        startReceiver(for: entry)

        if configuration.enableLogging, let logEvent {
            configuration.logHandler(DatagramSocketLogEvent(kind: logEvent))
        }
    }

    private func startReceiver(for entry: Entry) {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let data = try await entry.socket.receive()
                    self?.recordRoundtripSuccess()
                    if let continuation = self?.streamContinuation {
                        continuation.yield(data)
                    }
                } catch {
                    self?.handleReceiveError(error, entryId: entry.id)
                    break
                }
            }
        }
        stateLock.lock()
        if var stored = entries[entry.id] {
            stored.receiverTask = task
            entries[entry.id] = stored
        }
        stateLock.unlock()
    }

    private func handleReceiveError(_ error: Error, entryId: UUID) {
        stateLock.lock()
        guard let entry = entries.removeValue(forKey: entryId) else {
            stateLock.unlock()
            return
        }
        let shouldFinish: Bool
        if let socketError = error as? DatagramSocketError, socketError == .closed {
            shouldFinish = entries.isEmpty
        } else {
            shouldFinish = entries.isEmpty
        }
        stateLock.unlock()

        entry.socket.close()
        entry.receiverTask?.cancel()

        if shouldFinish {
            streamContinuation?.finish(throwing: error)
        }
    }

    private func currentSocket() -> DatagramSocket {
        stateLock.lock()
        let entry = currentSocketId.flatMap { entries[$0] }
        let socket = entry?.socket ?? entries.values.first?.socket
        stateLock.unlock()
        return socket ?? entries.values.first!.socket
    }

    private func currentLocalPort() -> UInt16? {
        stateLock.lock()
        let entry = currentSocketId.flatMap { entries[$0] }
        let port = entry?.localPort
        stateLock.unlock()
        return port
    }

    private static func makeEntry(
        host: String,
        port: UInt16,
        configuration: Configuration,
        openedAt: Date
    ) throws -> Entry {
        let socket = try configuration.socketFactory(host, port)
        let localPort = (socket as? DatagramSocketPortProviding)?.localPort
        return Entry(id: UUID(), socket: socket, openedAt: openedAt, localPort: localPort, receiverTask: nil)
    }
}

extension RoamingDatagramSocket: DatagramSocketPortProviding {
    var localPort: UInt16 {
        currentLocalPort() ?? 0
    }
}
