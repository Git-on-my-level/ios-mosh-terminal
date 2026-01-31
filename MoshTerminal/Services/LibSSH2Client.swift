#if LIBSSH2_AVAILABLE
import Foundation
import libssh2
import Darwin

final class LibSSH2Client: SSHClient, @unchecked Sendable {
    private static let channelWindowDefault: UInt32 = 2 * 1024 * 1024
    private static let channelPacketDefault: UInt32 = 32768
    private static let connectTimeoutSeconds: TimeInterval = 15
    private let queue = DispatchQueue(label: "com.moshterminal.ssh")
    private let hostKeyVerifier: SSHHostKeyVerifying?
    private let connectStateLock = NSLock()

    private var session: OpaquePointer?
    private var socketFD: Int32 = -1
    private var hostKeyFingerprint: String?
    private var connectedHost: String?
    private var connectedPort: Int?
    private var cancelRequested = false
    private var pendingSocketFD: Int32 = -1

    init(hostKeyVerifier: SSHHostKeyVerifying? = nil) {
        self.hostKeyVerifier = hostKeyVerifier
        LibSSH2Global.shared.initialize()
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        privateKey: Data,
        passphrase: String?
    ) async throws {
        resetCancellationState()
        let fingerprint = try await run {
            if self.session != nil {
                throw SSHClientError.alreadyConnected
            }
            let socketFD = try self.openSocket(host: host, port: port)
            self.socketFD = socketFD

            guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
                Self.closeSocket(socketFD)
                self.socketFD = -1
                throw SSHClientError.connectionFailed(message: "Failed to initialize SSH session.")
            }
            self.session = session
            libssh2_session_set_blocking(session, 1)
            libssh2_session_set_timeout(session, 15000)

            let handshake = libssh2_session_handshake(session, socketFD)
            guard handshake == 0 else {
                throw SSHClientError.connectionFailed(message: "Handshake failed (\(handshake)).")
            }

            let fingerprint = try Self.hostKeyFingerprintSHA256(session: session)
            self.hostKeyFingerprint = fingerprint
            self.connectedHost = host
            self.connectedPort = port
            return fingerprint
        }

        if let verifier = hostKeyVerifier {
            do {
                try await verifier.verify(hostname: host, port: port, fingerprint: fingerprint)
            } catch {
                await disconnect()
                throw error
            }
        }

        do {
            try await run {
                guard let session = self.session else {
                    throw SSHClientError.notConnected
                }
                let auth = try Self.authenticate(
                    session: session,
                    username: username,
                    privateKey: privateKey,
                    passphrase: passphrase
                )
                guard auth == 0 else {
                    throw SSHClientError.authenticationFailed
                }
            }
        } catch {
            await disconnect()
            throw error
        }
    }

    func fetchHostKeyFingerprint() async throws -> String {
        try await run {
            guard let fingerprint = self.hostKeyFingerprint else {
                throw SSHClientError.notConnected
            }
            return fingerprint
        }
    }

    func execute(command: String) async throws -> SSHCommandResult {
        try await run {
            guard let session = self.session else {
                throw SSHClientError.notConnected
            }

            guard let channel = libssh2_channel_open_ex(
                session,
                "session",
                UInt32("session".utf8.count),
                Self.channelWindowDefault,
                Self.channelPacketDefault,
                nil,
                0
            ) else {
                throw SSHClientError.connectionFailed(message: "Unable to open SSH channel.")
            }
            defer {
                libssh2_channel_close(channel)
                libssh2_channel_free(channel)
            }

            let execResult = command.withCString { commandCString in
                libssh2_channel_process_startup(
                    channel,
                    "exec",
                    UInt32("exec".utf8.count),
                    commandCString,
                    UInt32(strlen(commandCString))
                )
            }
            guard execResult == 0 else {
                throw SSHClientError.connectionFailed(message: "Command exec failed (\(execResult)).")
            }

            let (stdoutData, stderrData) = try Self.readChannelOutput(channel: channel)
            let exitStatus = libssh2_channel_get_exit_status(channel)

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return SSHCommandResult(stdout: stdout, stderr: stderr, exitStatus: Int32(exitStatus))
        }
    }

    func disconnect() async {
        await runIgnoringErrors {
            if let session = self.session {
                libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "", "")
                libssh2_session_free(session)
            }
            self.session = nil
            self.hostKeyFingerprint = nil
            self.connectedHost = nil
            self.connectedPort = nil
            if self.socketFD >= 0 {
                Self.closeSocket(self.socketFD)
                self.socketFD = -1
            }
        }
    }

    func cancel() async {
        if let pending = requestCancellation() {
            Self.closeSocket(pending)
        }
        await disconnect()
    }

    private func run<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try block())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runIgnoringErrors(_ block: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                block()
                continuation.resume()
            }
        }
    }

    struct AuthFunctions {
        let userauthPublicKeyFromMemory: (
            OpaquePointer,
            UnsafePointer<Int8>,
            Int,
            UnsafePointer<Int8>?,
            Int,
            UnsafePointer<Int8>,
            Int,
            UnsafePointer<Int8>?
        ) -> Int32
        let userauthPublicKeyFromFile: (
            OpaquePointer,
            UnsafePointer<Int8>,
            UInt32,
            UnsafePointer<Int8>?,
            UnsafePointer<Int8>,
            UnsafePointer<Int8>?
        ) -> Int32

        static let live = AuthFunctions(
            userauthPublicKeyFromMemory: { session, username, usernameLength, publicKey, publicKeyLength, privateKey, privateKeyLength, passphrase in
                Int32(libssh2_userauth_publickey_frommemory(
                    session,
                    username,
                    usernameLength,
                    publicKey,
                    publicKeyLength,
                    privateKey,
                    privateKeyLength,
                    passphrase
                ))
            },
            userauthPublicKeyFromFile: { session, username, usernameLength, publicKey, privateKeyPath, passphrase in
                Int32(libssh2_userauth_publickey_fromfile_ex(
                    session,
                    username,
                    usernameLength,
                    publicKey,
                    privateKeyPath,
                    passphrase
                ))
            }
        )
    }

    static func authenticate(
        session: OpaquePointer,
        username: String,
        privateKey: Data,
        passphrase: String?,
        authFunctions: AuthFunctions = .live
    ) throws -> Int32 {
        let memoryResult = try privateKey.withUnsafeBytes { privateKeyBuffer in
            guard let privateKeyBase = privateKeyBuffer.bindMemory(to: Int8.self).baseAddress else {
                throw SSHClientError.authenticationFailed
            }
            return try username.withCString { usernameCString in
                if let passphrase = passphrase {
                    return passphrase.withCString { passphraseCString in
                        authFunctions.userauthPublicKeyFromMemory(
                            session,
                            usernameCString,
                            username.utf8.count,
                            nil,
                            0,
                            privateKeyBase,
                            privateKey.count,
                            passphraseCString
                        )
                    }
                } else {
                    authFunctions.userauthPublicKeyFromMemory(
                        session,
                        usernameCString,
                        username.utf8.count,
                        nil,
                        0,
                        privateKeyBase,
                        privateKey.count,
                        nil
                    )
                }
            }
        }
        return memoryResult
    }

    private static func readChannelOutput(channel: OpaquePointer) throws -> (Data, Data) {
        var stdoutData = Data()
        var stderrData = Data()
        var stdoutDone = false
        var stderrDone = false
        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while !stdoutDone || !stderrDone {
            if !stdoutDone {
                let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                    let pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: Int8.self)
                    return libssh2_channel_read_ex(channel, 0, pointer, bufferSize)
                }
                if bytesRead > 0 {
                    stdoutData.append(buffer, count: bytesRead)
                } else if bytesRead == 0 {
                    stdoutDone = true
                } else {
                    throw SSHClientError.connectionFailed(message: "Failed to read stdout (\(bytesRead)).")
                }
            }

            if !stderrDone {
                let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                    let pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: Int8.self)
                    return libssh2_channel_read_ex(channel, 1, pointer, bufferSize)
                }
                if bytesRead > 0 {
                    stderrData.append(buffer, count: bytesRead)
                } else if bytesRead == 0 {
                    stderrDone = true
                } else {
                    throw SSHClientError.connectionFailed(message: "Failed to read stderr (\(bytesRead)).")
                }
            }
        }

        return (stdoutData, stderrData)
    }

    private static func hostKeyFingerprintSHA256(session: OpaquePointer) throws -> String {
        guard let hashPointer = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_SHA256) else {
            throw SSHClientError.connectionFailed(message: "Unable to read host key fingerprint.")
        }
        let hashData = Data(bytes: hashPointer, count: 32)
        return "SHA256:\(hashData.base64EncodedString())"
    }

    private func openSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let result else {
            throw SSHClientError.connectionFailed(message: "Unable to resolve host.")
        }
        defer { freeaddrinfo(result) }

        let deadline = DispatchTime.now().advanced(by: .seconds(Int(Self.connectTimeoutSeconds)))
        var pointer: UnsafeMutablePointer<addrinfo>? = result
        var lastError: String?
        while let addrInfo = pointer {
            try checkCancellation()
            let remaining = remainingTimeoutMilliseconds(until: deadline)
            if remaining == 0 {
                throw SSHClientError.connectionFailed(message: "Connection timed out.")
            }
            let socketFD = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
            if socketFD >= 0 {
                setPendingSocket(socketFD)
                if isCancelRequested() {
                    if clearPendingSocket(socketFD) {
                        Self.closeSocket(socketFD)
                    }
                    throw SSHClientError.cancelled
                }
                let originalFlags = fcntl(socketFD, F_GETFL, 0)
                if originalFlags >= 0 {
                    if fcntl(socketFD, F_SETFL, originalFlags | O_NONBLOCK) < 0 {
                        lastError = "Failed to set socket non-blocking mode."
                        if clearPendingSocket(socketFD) {
                            Self.closeSocket(socketFD)
                        }
                        pointer = addrInfo.pointee.ai_next
                        continue
                    }
                } else {
                    lastError = "Failed to read socket flags."
                    if clearPendingSocket(socketFD) {
                        Self.closeSocket(socketFD)
                    }
                    pointer = addrInfo.pointee.ai_next
                    continue
                }
                let connectResult = Darwin.connect(socketFD, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
                if connectResult == 0 {
                    if isCancelRequested() {
                        _ = clearPendingSocket(socketFD)
                        Self.closeSocket(socketFD)
                        throw SSHClientError.cancelled
                    }
                    _ = fcntl(socketFD, F_SETFL, originalFlags)
                    _ = clearPendingSocket(socketFD)
                    return socketFD
                }

                if errno == EINPROGRESS {
                    do {
                        let connected = try waitForConnect(socketFD: socketFD, deadline: deadline)
                        if connected {
                            if isCancelRequested() {
                                _ = clearPendingSocket(socketFD)
                                Self.closeSocket(socketFD)
                                throw SSHClientError.cancelled
                            }
                            _ = fcntl(socketFD, F_SETFL, originalFlags)
                            _ = clearPendingSocket(socketFD)
                            return socketFD
                        }
                        lastError = "Connection timed out."
                    } catch {
                        _ = clearPendingSocket(socketFD)
                        if let sshError = error as? SSHClientError {
                            if sshError == .cancelled {
                                Self.closeSocket(socketFD)
                                throw sshError
                            }
                            if case .connectionFailed(let message) = sshError {
                                lastError = message
                            } else {
                                lastError = "Connection failed."
                            }
                        } else {
                            lastError = "Connection failed."
                        }
                    }
                } else {
                    lastError = socketErrorDescription(prefix: "Connect failed")
                }

                if clearPendingSocket(socketFD) {
                    Self.closeSocket(socketFD)
                }
            }
            pointer = addrInfo.pointee.ai_next
        }

        let message = lastError ?? "Unable to connect to host."
        throw SSHClientError.connectionFailed(message: message)
    }

    private static func closeSocket(_ socketFD: Int32) {
        close(socketFD)
    }

    private func waitForConnect(socketFD: Int32, deadline: DispatchTime) throws -> Bool {
        var pollFD = pollfd(fd: socketFD, events: Int16(POLLOUT), revents: 0)
        while true {
            try checkCancellation()
            let timeout = remainingTimeoutMilliseconds(until: deadline)
            if timeout == 0 {
                return false
            }
            let result = withUnsafeMutablePointer(to: &pollFD) { pointer in
                poll(pointer, 1, timeout)
            }
            if result > 0 {
                if pollFD.revents & Int16(POLLNVAL | POLLERR | POLLHUP) != 0 {
                    let errorMessage = socketErrorDescription(prefix: "Connect failed")
                    throw SSHClientError.connectionFailed(message: errorMessage)
                }
                let socketError = getSocketError(socketFD)
                if socketError == 0 {
                    return true
                }
                let message = socketErrorDescription(prefix: "Connect failed", errnoOverride: socketError)
                throw SSHClientError.connectionFailed(message: message)
            } else if result == 0 {
                return false
            } else if errno == EINTR {
                continue
            } else {
                let message = socketErrorDescription(prefix: "Poll failed")
                throw SSHClientError.connectionFailed(message: message)
            }
        }
    }

    private func remainingTimeoutMilliseconds(until deadline: DispatchTime) -> Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        let deadlineNs = deadline.uptimeNanoseconds
        guard deadlineNs > now else { return 0 }
        let remainingNs = deadlineNs - now
        let remainingMs = remainingNs / 1_000_000
        if remainingMs == 0 {
            return 1
        }
        if remainingMs > UInt64(Int32.max) {
            return Int32.max
        }
        return Int32(remainingMs)
    }

    private func socketErrorDescription(prefix: String, errnoOverride: Int32? = nil) -> String {
        let errorCode = errnoOverride ?? Int32(errno)
        guard let errorCString = strerror(errorCode) else {
            return "\(prefix) (\(errorCode))."
        }
        let message = String(cString: errorCString)
        return "\(prefix): \(message) (\(errorCode))."
    }

    private func getSocketError(_ socketFD: Int32) -> Int32 {
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout.size(ofValue: error))
        if getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &length) != 0 {
            return Int32(errno)
        }
        return error
    }

    private func resetCancellationState() {
        connectStateLock.lock()
        cancelRequested = false
        pendingSocketFD = -1
        connectStateLock.unlock()
    }

    private func requestCancellation() -> Int32? {
        connectStateLock.lock()
        cancelRequested = true
        let socketFD = pendingSocketFD
        pendingSocketFD = -1
        connectStateLock.unlock()
        return socketFD >= 0 ? socketFD : nil
    }

    private func setPendingSocket(_ socketFD: Int32) {
        connectStateLock.lock()
        pendingSocketFD = socketFD
        connectStateLock.unlock()
    }

    private func clearPendingSocket(_ socketFD: Int32) -> Bool {
        connectStateLock.lock()
        let shouldClear = pendingSocketFD == socketFD
        if shouldClear {
            pendingSocketFD = -1
        }
        connectStateLock.unlock()
        return shouldClear
    }

    private func isCancelRequested() -> Bool {
        connectStateLock.lock()
        let requested = cancelRequested
        connectStateLock.unlock()
        return requested
    }

    private func checkCancellation() throws {
        if isCancelRequested() {
            throw SSHClientError.cancelled
        }
    }
}

private final class LibSSH2Global {
    static let shared = LibSSH2Global()
    private var initialized = false

    func initialize() {
        if initialized { return }
        libssh2_init(0)
        initialized = true
    }

    deinit {
        if initialized {
            libssh2_exit()
        }
    }
}
#endif
