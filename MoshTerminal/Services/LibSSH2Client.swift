#if canImport(libssh2)
import Foundation
import libssh2
import Darwin

final class LibSSH2Client: SSHClient, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.moshterminal.ssh")
    private let hostKeyVerifier: SSHHostKeyVerifying?

    private var session: OpaquePointer?
    private var socketFD: Int32 = -1
    private var hostKeyFingerprint: String?
    private var connectedHost: String?
    private var connectedPort: Int?

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
        let fingerprint = try await run {
            if session != nil {
                throw SSHClientError.alreadyConnected
            }
            let socketFD = try Self.openSocket(host: host, port: port)
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
                guard let session = session else {
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
            guard let fingerprint = hostKeyFingerprint else {
                throw SSHClientError.notConnected
            }
            return fingerprint
        }
    }

    func execute(command: String) async throws -> SSHCommandResult {
        try await run {
            guard let session = session else {
                throw SSHClientError.notConnected
            }

            guard let channel = libssh2_channel_open_session(session) else {
                throw SSHClientError.connectionFailed(message: "Unable to open SSH channel.")
            }
            defer {
                libssh2_channel_close(channel)
                libssh2_channel_free(channel)
            }

            let execResult = command.withCString { commandCString in
                libssh2_channel_exec(channel, commandCString)
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
            if let session = session {
                libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "", "")
                libssh2_session_free(session)
            }
            session = nil
            hostKeyFingerprint = nil
            connectedHost = nil
            connectedPort = nil
            if socketFD >= 0 {
                Self.closeSocket(socketFD)
                socketFD = -1
            }
        }
    }

    func cancel() async {
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

    private static func authenticate(
        session: OpaquePointer,
        username: String,
        privateKey: Data,
        passphrase: String?
    ) throws -> Int32 {
        return try privateKey.withUnsafeBytes { privateKeyBuffer in
            guard let privateKeyBase = privateKeyBuffer.bindMemory(to: Int8.self).baseAddress else {
                throw SSHClientError.authenticationFailed
            }
            return try username.withCString { usernameCString in
                if let passphrase = passphrase {
                    return try passphrase.withCString { passphraseCString in
                        let result = libssh2_userauth_publickey_frommemory(
                            session,
                            usernameCString,
                            username.utf8.count,
                            nil,
                            0,
                            privateKeyBase,
                            privateKey.count,
                            passphraseCString
                        )
                        return Int32(result)
                    }
                } else {
                    let result = libssh2_userauth_publickey_frommemory(
                        session,
                        usernameCString,
                        username.utf8.count,
                        nil,
                        0,
                        privateKeyBase,
                        privateKey.count,
                        nil
                    )
                    return Int32(result)
                }
            }
        }
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

    private static func openSocket(host: String, port: Int) throws -> Int32 {
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

        var pointer: UnsafeMutablePointer<addrinfo>? = result
        while let addrInfo = pointer {
            let socketFD = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
            if socketFD >= 0 {
                let connectResult = connect(socketFD, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
                if connectResult == 0 {
                    return socketFD
                }
                close(socketFD)
            }
            pointer = addrInfo.pointee.ai_next
        }

        throw SSHClientError.connectionFailed(message: "Unable to connect to host.")
    }

    private static func closeSocket(_ socketFD: Int32) {
        close(socketFD)
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
