import XCTest
@testable import MoshTerminal

#if canImport(MoshClient) && canImport(libssh2)
final class MoshE2EIntegrationTests: XCTestCase {
    func testMoshBootstrapAndHandshake() async throws {
        let env = ProcessInfo.processInfo.environment
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
        let connectInfo = try await bootstrapper.bootstrap(
            host: hostProfile,
            privateKey: privateKey,
            passphrase: nil,
            hostKeyPrompter: hostKeyPrompter
        )

        let engine = MoshClientEngine()
        let timeout = Self.e2eTimeout(from: env)
        let completion = expectation(description: "mosh handshake")
        var handshakeError: Error?

        engine.onStateChange = { state in
            switch state {
            case .connected:
                completion.fulfill()
            case .failed(let error):
                handshakeError = error
                completion.fulfill()
            case .disconnected:
                handshakeError = MoshEngineError.startFailed(message: "Mosh client disconnected during handshake.")
                completion.fulfill()
            case .idle, .starting:
                break
            }
        }

        defer {
            Task { await engine.stop() }
        }

        try await engine.start(connectInfo: connectInfo, initialTerminalSize: TerminalSize(cols: 80, rows: 24))

        await fulfillment(of: [completion], timeout: timeout)

        if let handshakeError {
            XCTFail("Mosh handshake failed: \(handshakeError)")
        }
    }

    private static func e2eTimeout(from env: [String: String]) -> TimeInterval {
        if let value = env["MOSH_E2E_TIMEOUT"], let parsed = Double(value), parsed > 0 {
            return parsed
        }
        return 15
    }
}
#else
final class MoshE2EIntegrationTests: XCTestCase {
    func testMoshBootstrapAndHandshake() throws {
        throw XCTSkip("Mosh or libssh2 is unavailable in this build.")
    }
}
#endif
