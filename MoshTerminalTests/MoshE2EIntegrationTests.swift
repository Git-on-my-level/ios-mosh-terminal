import XCTest
@testable import MoshTerminal

final class MoshE2EIntegrationTests: XCTestCase {
    func testMoshBootstrapAndHandshake() async throws {
        var env = ProcessInfo.processInfo.environment
        if let fallback = Self.loadHarnessEnv(over: env) {
            for (key, value) in fallback {
                if env[key]?.isEmpty ?? true {
                    env[key] = value
                }
            }
        }

        guard let host = env["MOSH_HOST"], !host.isEmpty,
              let user = env["MOSH_USER"], !user.isEmpty,
              let portString = env["MOSH_SSH_PORT"],
              let port = Int(portString),
              let keyPath = env["MOSH_KEY_PATH"], !keyPath.isEmpty else {
            throw XCTSkip("Missing MOSH_* env vars. Run scripts/e2e_mosh_test.sh to execute this test.")
        }

        let keyURL = URL(fileURLWithPath: keyPath)
        let privateKey = try Data(contentsOf: keyURL)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let store = JSONStore(fileURL: tempDir.appendingPathComponent("store.json"))
        let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
        let sshClientFactory = DefaultSSHClientFactory.make(repository: trustedHostKeyRepository)
        let bootstrapper = MoshBootstrapper(sshClientFactory: sshClientFactory)

        let hostProfile = HostProfile(
            displayName: "E2E",
            hostname: host,
            username: user,
            sshPort: port,
            keyRefId: "e2e-key"
        )

        let hostKeyPrompter = SSHHostKeyPrompt { _ in true }
        let bootstrapResult: MoshBootstrapResult
        do {
            bootstrapResult = try await bootstrapper.bootstrap(
                host: hostProfile,
                privateKey: privateKey,
                passphrase: nil,
                hostKeyPrompter: hostKeyPrompter
            )
        } catch let error as SSHClientError where error == .libraryUnavailable {
            XCTFail("libssh2 is unavailable in this build. Run scripts/build_xcframeworks.sh to build it.")
            return
        }

        let engine = NativeMoshEngine()
        let timeout = Self.e2eTimeout(from: env)
        let connected = expectation(description: "mosh connected")
        let outputReceived = expectation(description: "mosh output")
        let outputBuffer = OutputBuffer(limit: 12_000)
        let sentinel = env["MOSH_E2E_SENTINEL"] ?? "__MOSH_E2E_OK__"
        let command = env["MOSH_E2E_COMMAND"] ?? "printf '__MOSH_E2E_OK__\\n'"
        let handshakeState = HandshakeState()

        engine.onOutput = { data in
            Task {
                await outputBuffer.append(data)
                if await outputBuffer.contains(sentinel) {
                    outputReceived.fulfill()
                }
            }
        }

        engine.onStateChange = { state in
            switch state {
            case .connected:
                connected.fulfill()
            case .failed(let error):
                Task { await handshakeState.set(error) }
                connected.fulfill()
            case .disconnected:
                Task { await handshakeState.set(MoshEngineError.startFailed(message: "Mosh client disconnected during handshake.")) }
                connected.fulfill()
            case .idle, .starting:
                break
            }
        }

        defer {
            Task { await engine.stop() }
        }

        try await engine.start(
            connectInfo: bootstrapResult.connectInfo,
            initialTerminalSize: TerminalSize(cols: 80, rows: 24)
        )

        let connectedResult = await XCTWaiter().fulfillment(of: [connected], timeout: timeout)
        if connectedResult != .completed {
            XCTFail("Timed out waiting for mosh connection (result: \(connectedResult)).")
            return
        }

        if let handshakeError = await handshakeState.get() {
            XCTFail("Mosh handshake failed: \(handshakeError)")
            return
        }

        await engine.sendInput(Data("\(command)\n".utf8))

        let outputResult = await XCTWaiter().fulfillment(of: [outputReceived], timeout: timeout)
        if outputResult != .completed {
            let debug = await engine.debugSnapshot()
            let tail = await outputBuffer.tail(maxCharacters: 240)
            XCTFail("Timed out waiting for sentinel output (result: \(outputResult)). Debug: \(debug). Output tail: \(tail)")
            return
        }

        if !(await outputBuffer.contains(sentinel)) {
            let debug = await engine.debugSnapshot()
            let tail = await outputBuffer.tail(maxCharacters: 240)
            XCTFail("Did not observe sentinel output. Debug: \(debug). Output tail: \(tail)")
        }
    }

    private static func e2eTimeout(from env: [String: String]) -> TimeInterval {
        if let value = env["MOSH_E2E_TIMEOUT"], let parsed = Double(value), parsed > 0 {
            return parsed
        }
        return 15
    }

    private static func loadHarnessEnv(over env: [String: String]) -> [String: String]? {
        let stateFile = env["MOSH_HARNESS_STATE_FILE"] ?? "/tmp/mosh-harness.state"
        guard let statePath = readFile(at: stateFile) else { return nil }
        let trimmed = statePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let envPath = URL(fileURLWithPath: trimmed).appendingPathComponent("connection.env").path
        guard let envContents = readFile(at: envPath) else { return nil }
        return parseExportEnv(envContents)
    }

    private static func readFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parseExportEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("export ") else { continue }
            let assignment = line.dropFirst("export ".count)
            guard let equalsIndex = assignment.firstIndex(of: "=") else { continue }
            let key = assignment[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            var value = assignment[assignment.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                result[String(key)] = String(value)
            }
        }
        return result
    }
}

private actor OutputBuffer {
    private var data = Data()
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        data.append(chunk)
        if data.count > limit {
            data.removeFirst(data.count - limit)
        }
    }

    func contains(_ needle: String) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        return text.contains(needle)
    }

    func tail(maxCharacters: Int) -> String {
        let text = String(decoding: data, as: UTF8.self)
        guard text.count > maxCharacters else { return sanitize(text) }
        let startIndex = text.index(text.endIndex, offsetBy: -maxCharacters)
        return sanitize(String(text[startIndex...]))
    }

    private func sanitize(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            scalar.value == 10 || scalar.value == 13 || scalar.value == 9 || scalar.value >= 32
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

private actor HandshakeState {
    private var error: Error?

    func set(_ error: Error) {
        self.error = error
    }

    func get() -> Error? {
        error
    }
}
