import XCTest
@testable import MoshTerminal

final class MoshBootstrapperTests: XCTestCase {
    func testParsesConnectInfoFromStdout() throws {
        let result = SSHCommandResult(
            stdout: "MOSH CONNECT 60001 abcDEF+/=\n",
            stderr: "",
            exitStatus: 0
        )

        let info = try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "example.com")

        XCTAssertEqual(info.udpPort, 60001)
        XCTAssertEqual(info.sessionKey, "abcDEF+/=")
        XCTAssertEqual(info.serverAddress, "example.com")
    }

    func testParsesConnectInfoFromMixedOutput() throws {
        let result = SSHCommandResult(
            stdout: "Some banner\nMOSH CONNECT 60002 key123=\nMore text",
            stderr: "",
            exitStatus: 0
        )

        let info = try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "host")

        XCTAssertEqual(info.udpPort, 60002)
        XCTAssertEqual(info.sessionKey, "key123=")
    }

    func testDetectsMissingMoshServer() {
        let result = SSHCommandResult(
            stdout: "",
            stderr: "mosh-server: command not found",
            exitStatus: 127
        )

        XCTAssertThrowsError(try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "host")) { error in
            XCTAssertEqual(error as? MoshBootstrapError, .moshServerMissing)
        }
    }

    func testDetectsNonUtf8LocaleError() {
        let result = SSHCommandResult(
            stdout: "",
            stderr: "mosh-server needs a UTF-8 locale",
            exitStatus: 1
        )

        XCTAssertThrowsError(try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "host")) { error in
            XCTAssertEqual(error as? MoshBootstrapError, .nonUtf8Locale)
        }
    }

    func testManagedTmuxBootstrapUsesManagedLaunchWhenTmuxAvailable() async throws {
        let host = HostProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!,
            displayName: "Managed",
            hostname: "example.com",
            username: "mosh",
            keyRefId: "key-1"
        )
        let client = StubSSHClient()
        client.stub(command: ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand, result: .success(.successNoOutput))
        client.stub(
            command: ManagedRemoteCommandBuilder.managedTmuxLaunchCommand(for: host.id),
            result: .success(.connect(port: 60010, key: "managed="))
        )

        let bootstrapper = MoshBootstrapper(sshClientFactory: { _ in client })
        let result = try await bootstrapper.bootstrap(
            host: host,
            privateKey: Data("key".utf8),
            passphrase: nil,
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        XCTAssertEqual(result.persistenceOutcome, .managedTmuxActive)
        XCTAssertEqual(result.connectInfo.udpPort, 60010)
        XCTAssertEqual(
            client.executedCommands,
            [
                ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand,
                ManagedRemoteCommandBuilder.managedTmuxLaunchCommand(for: host.id)
            ]
        )
    }

    func testManagedTmuxMissingWithUnknownConsentFallsBackAndIncludesInstallCommand() async throws {
        let host = HostProfile(
            displayName: "Managed",
            hostname: "example.com",
            username: "mosh",
            keyRefId: "key-1",
            tmuxSetupConsent: .unknown
        )
        let client = StubSSHClient()
        client.stub(command: ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand, result: .success(.failureStatus))
        client.stub(
            command: ManagedRemoteCommandBuilder.packageManagerDetectionCommand,
            result: .success(.stdout("apt-get\n"))
        )
        client.stub(command: ManagedRemoteCommandBuilder.currentUserIdCommand, result: .success(.stdout("1000\n")))
        client.stub(command: ManagedRemoteCommandBuilder.plainShellLaunchCommand, result: .success(.connect(port: 60011, key: "plain=")))

        let bootstrapper = MoshBootstrapper(sshClientFactory: { _ in client })
        let result = try await bootstrapper.bootstrap(
            host: host,
            privateKey: Data("key".utf8),
            passphrase: nil,
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        XCTAssertEqual(
            result.persistenceOutcome,
            .fallbackPlainShell(
                reason: .tmuxMissingConsentRequired(
                    installCommand: "sudo -n apt-get update && sudo -n apt-get install -y tmux"
                )
            )
        )
        XCTAssertEqual(result.connectInfo.udpPort, 60011)
        XCTAssertEqual(
            client.executedCommands,
            [
                ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand,
                ManagedRemoteCommandBuilder.packageManagerDetectionCommand,
                ManagedRemoteCommandBuilder.currentUserIdCommand,
                ManagedRemoteCommandBuilder.plainShellLaunchCommand
            ]
        )
    }

    func testManagedTmuxMissingWithApprovedConsentInstallsAndUsesManagedLaunch() async throws {
        let host = HostProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000EF01")!,
            displayName: "Managed",
            hostname: "example.com",
            username: "mosh",
            keyRefId: "key-1",
            tmuxSetupConsent: .approved
        )
        let installCommand = "sudo -n apt-get update && sudo -n apt-get install -y tmux"

        let client = StubSSHClient()
        client.stub(command: ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand, result: .success(.failureStatus))
        client.stub(
            command: ManagedRemoteCommandBuilder.packageManagerDetectionCommand,
            result: .success(.stdout("apt-get\n"))
        )
        client.stub(command: ManagedRemoteCommandBuilder.currentUserIdCommand, result: .success(.stdout("1000\n")))
        client.stub(command: installCommand, result: .success(.successNoOutput))
        client.stub(command: ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand, result: .success(.successNoOutput))
        client.stub(
            command: ManagedRemoteCommandBuilder.managedTmuxLaunchCommand(for: host.id),
            result: .success(.connect(port: 60012, key: "managed="))
        )

        let bootstrapper = MoshBootstrapper(sshClientFactory: { _ in client })
        let result = try await bootstrapper.bootstrap(
            host: host,
            privateKey: Data("key".utf8),
            passphrase: nil,
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        XCTAssertEqual(result.persistenceOutcome, .managedTmuxActive)
        XCTAssertEqual(result.connectInfo.udpPort, 60012)
        XCTAssertEqual(
            client.executedCommands,
            [
                ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand,
                ManagedRemoteCommandBuilder.packageManagerDetectionCommand,
                ManagedRemoteCommandBuilder.currentUserIdCommand,
                installCommand,
                ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand,
                ManagedRemoteCommandBuilder.managedTmuxLaunchCommand(for: host.id)
            ]
        )
    }

    func testManagedTmuxInstallFailureFallsBackToPlainShell() async throws {
        let host = HostProfile(
            displayName: "Managed",
            hostname: "example.com",
            username: "mosh",
            keyRefId: "key-1",
            tmuxSetupConsent: .approved
        )
        let installCommand = "sudo -n apt-get update && sudo -n apt-get install -y tmux"

        let client = StubSSHClient()
        client.stub(command: ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand, result: .success(.failureStatus))
        client.stub(
            command: ManagedRemoteCommandBuilder.packageManagerDetectionCommand,
            result: .success(.stdout("apt-get\n"))
        )
        client.stub(command: ManagedRemoteCommandBuilder.currentUserIdCommand, result: .success(.stdout("1000\n")))
        client.stub(command: installCommand, result: .success(.stderr("sudo: a password is required", exitStatus: 1)))
        client.stub(command: ManagedRemoteCommandBuilder.plainShellLaunchCommand, result: .success(.connect(port: 60013, key: "plain=")))

        let bootstrapper = MoshBootstrapper(sshClientFactory: { _ in client })
        let result = try await bootstrapper.bootstrap(
            host: host,
            privateKey: Data("key".utf8),
            passphrase: nil,
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        XCTAssertEqual(
            result.persistenceOutcome,
            .fallbackPlainShell(
                reason: .tmuxInstallFailed(
                    installCommand: installCommand,
                    details: "sudo: a password is required"
                )
            )
        )
        XCTAssertEqual(result.connectInfo.udpPort, 60013)
    }

    func testPlainShellModeAlwaysUsesPlainShellLaunch() async throws {
        let host = HostProfile(
            displayName: "Plain",
            hostname: "example.com",
            username: "mosh",
            keyRefId: "key-1",
            sessionPersistenceMode: .plainShell
        )
        let client = StubSSHClient()
        client.stub(command: ManagedRemoteCommandBuilder.plainShellLaunchCommand, result: .success(.connect(port: 60014, key: "plain=")))

        let bootstrapper = MoshBootstrapper(sshClientFactory: { _ in client })
        let result = try await bootstrapper.bootstrap(
            host: host,
            privateKey: Data("key".utf8),
            passphrase: nil,
            hostKeyPrompter: SSHHostKeyPrompt { _ in true }
        )

        XCTAssertEqual(result.persistenceOutcome, .fallbackPlainShell(reason: .hostPreferencePlainShell))
        XCTAssertEqual(client.executedCommands, [ManagedRemoteCommandBuilder.plainShellLaunchCommand])
    }
}

private final class StubSSHClient: SSHClient, @unchecked Sendable {
    private var responsesByCommand: [String: [Result<SSHCommandResult, Error>]] = [:]
    private(set) var executedCommands: [String] = []

    func stub(command: String, result: Result<SSHCommandResult, Error>) {
        responsesByCommand[command, default: []].append(result)
    }

    func connect(
        host: String,
        port: Int,
        username: String,
        privateKey: Data,
        passphrase: String?
    ) async throws {
        _ = host
        _ = port
        _ = username
        _ = privateKey
        _ = passphrase
    }

    func fetchHostKeyFingerprint() async throws -> String {
        "SHA256:test"
    }

    func execute(command: String) async throws -> SSHCommandResult {
        executedCommands.append(command)
        guard var queue = responsesByCommand[command], !queue.isEmpty else {
            throw SSHClientError.commandFailed(exitStatus: 127, stderr: "No stub for command: \(command)")
        }
        let next = queue.removeFirst()
        responsesByCommand[command] = queue
        return try next.get()
    }

    func disconnect() async {}
    func cancel() async {}
}

private extension SSHCommandResult {
    static let successNoOutput = SSHCommandResult(stdout: "", stderr: "", exitStatus: 0)
    static let failureStatus = SSHCommandResult(stdout: "", stderr: "", exitStatus: 1)

    static func connect(port: Int, key: String) -> SSHCommandResult {
        SSHCommandResult(
            stdout: "MOSH CONNECT \(port) \(key)\n",
            stderr: "",
            exitStatus: 0
        )
    }

    static func stdout(_ text: String) -> SSHCommandResult {
        SSHCommandResult(stdout: text, stderr: "", exitStatus: 0)
    }

    static func stderr(_ text: String, exitStatus: Int32) -> SSHCommandResult {
        SSHCommandResult(stdout: "", stderr: text, exitStatus: exitStatus)
    }
}
