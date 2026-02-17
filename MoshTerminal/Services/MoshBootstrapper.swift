import Foundation

enum MoshBootstrapError: Error, LocalizedError, Equatable {
    case moshServerMissing
    case nonUtf8Locale
    case unexpectedOutput(message: String)

    var errorDescription: String? {
        switch self {
        case .moshServerMissing:
            return "mosh-server was not found on the host. Install mosh-server and try again."
        case .nonUtf8Locale:
            return "mosh-server requires a UTF-8 locale on the host. Configure a UTF-8 locale and try again."
        case .unexpectedOutput(let message):
            return "Unexpected mosh-server output: \(message)"
        }
    }
}

private enum ManagedRemotePackageManager: String, CaseIterable {
    case aptGet = "apt-get"
    case dnf
    case yum
    case zypper
    case pacman
    case apk
    case brew
    case pkg

    var requiresPrivilegeEscalation: Bool {
        switch self {
        case .aptGet, .dnf, .yum, .zypper, .pacman, .apk:
            return true
        case .brew, .pkg:
            return false
        }
    }

    func installTmuxCommand(useSudo: Bool) -> String {
        let sudoPrefix = useSudo ? "sudo -n " : ""
        switch self {
        case .aptGet:
            return "\(sudoPrefix)apt-get update && \(sudoPrefix)apt-get install -y tmux"
        case .dnf:
            return "\(sudoPrefix)dnf install -y tmux"
        case .yum:
            return "\(sudoPrefix)yum install -y tmux"
        case .zypper:
            return "\(sudoPrefix)zypper --non-interactive install tmux"
        case .pacman:
            return "\(sudoPrefix)pacman -Sy --noconfirm tmux"
        case .apk:
            return "\(sudoPrefix)apk add tmux"
        case .brew:
            return "brew install tmux"
        case .pkg:
            return "pkg install -y tmux"
        }
    }
}

struct ManagedRemoteCommandBuilder {
    static let plainShellLaunchCommand = "mosh-server new"
    static let tmuxPresenceCheckCommand = "command -v tmux >/dev/null 2>&1"
    static let currentUserIdCommand = "id -u"

    static let packageManagerDetectionCommand = """
    if command -v apt-get >/dev/null 2>&1; then echo apt-get; \
    elif command -v dnf >/dev/null 2>&1; then echo dnf; \
    elif command -v yum >/dev/null 2>&1; then echo yum; \
    elif command -v zypper >/dev/null 2>&1; then echo zypper; \
    elif command -v pacman >/dev/null 2>&1; then echo pacman; \
    elif command -v apk >/dev/null 2>&1; then echo apk; \
    elif command -v brew >/dev/null 2>&1; then echo brew; \
    elif command -v pkg >/dev/null 2>&1; then echo pkg; \
    else echo none; fi
    """

    static func managedSessionName(for hostId: UUID) -> String {
        let compact = hostId.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "moshterminal_\(compact.prefix(8))"
    }

    static func managedTmuxLaunchCommand(for hostId: UUID) -> String {
        let sessionName = managedSessionName(for: hostId)
        return "mosh-server new -- tmux -u new-session -A -s \(sessionName)"
    }
}

final class MoshBootstrapper: Sendable {
    private let sshClientFactory: SSHClientFactory

    init(sshClientFactory: @escaping SSHClientFactory) {
        self.sshClientFactory = sshClientFactory
    }

    func bootstrap(
        host: HostProfile,
        privateKey: Data,
        passphrase: String?,
        hostKeyPrompter: SSHHostKeyPrompting
    ) async throws -> MoshBootstrapResult {
        let client = sshClientFactory(hostKeyPrompter)
        defer {
            Task { await client.disconnect() }
        }

        try await client.connect(
            host: host.hostname,
            port: host.sshPort,
            username: host.username,
            privateKey: privateKey,
            passphrase: passphrase
        )

        switch host.sessionPersistenceMode {
        case .plainShell:
            return try await bootstrapPlainShell(
                client: client,
                host: host,
                outcome: .fallbackPlainShell(reason: .hostPreferencePlainShell)
            )
        case .managedTmux:
            return try await bootstrapManagedTmux(client: client, host: host)
        }
    }

    static func parseConnectInfo(
        from result: SSHCommandResult,
        serverAddress: String
    ) throws -> MoshConnectInfo {
        let output = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = matchConnectLine(in: output) {
            guard let udpPort = Int(match.port), (1...65535).contains(udpPort) else {
                throw MoshBootstrapError.unexpectedOutput(message: "Invalid UDP port in output.")
            }
            return MoshConnectInfo(
                udpPort: udpPort,
                sessionKey: match.key,
                serverAddress: serverAddress
            )
        }

        if isMissingMoshServer(output: output, exitStatus: result.exitStatus) {
            throw MoshBootstrapError.moshServerMissing
        }

        if isNonUtf8Locale(output: output) {
            throw MoshBootstrapError.nonUtf8Locale
        }

        let message = output.isEmpty ? "No output returned." : truncated(output)
        throw MoshBootstrapError.unexpectedOutput(message: message)
    }

    private static func matchConnectLine(in output: String) -> (port: String, key: String)? {
        guard !output.isEmpty else { return nil }
        let pattern = #"(?m)^MOSH CONNECT ([0-9]+) ([A-Za-z0-9+/=]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range) else {
            return nil
        }
        guard match.numberOfRanges == 3,
              let portRange = Range(match.range(at: 1), in: output),
              let keyRange = Range(match.range(at: 2), in: output) else {
            return nil
        }
        let port = String(output[portRange])
        let key = String(output[keyRange])
        return (port, key)
    }

    private static func isMissingMoshServer(output: String, exitStatus: Int32) -> Bool {
        if exitStatus == 127 { return true }
        let lower = output.lowercased()
        let indicators = [
            "mosh-server: not found",
            "mosh-server: command not found",
            "command not found",
            "no such file or directory"
        ]
        return indicators.contains { lower.contains($0) }
    }

    private static func isNonUtf8Locale(output: String) -> Bool {
        let lower = output.lowercased()
        let mentionsUtf8 = lower.contains("utf-8") || lower.contains("utf8")
        return mentionsUtf8 && lower.contains("locale")
    }

    private static func truncated(_ output: String, limit: Int = 200) -> String {
        guard output.count > limit else { return output }
        let index = output.index(output.startIndex, offsetBy: limit)
        return String(output[..<index]) + "..."
    }

    private enum TmuxAvailability {
        case available
        case missing(installCommand: String?)
    }

    private func bootstrapManagedTmux(
        client: SSHClient,
        host: HostProfile
    ) async throws -> MoshBootstrapResult {
        let availability: TmuxAvailability
        do {
            availability = try await detectTmuxAvailability(client: client)
        } catch {
            return try await bootstrapPlainShell(
                client: client,
                host: host,
                outcome: .fallbackPlainShell(
                    reason: .tmuxLaunchFailed(message: Self.truncated(error.localizedDescription))
                )
            )
        }
        switch availability {
        case .available:
            return try await bootstrapManagedTmuxLaunch(client: client, host: host)
        case .missing(let installCommand):
            guard let installCommand else {
                return try await bootstrapPlainShell(
                    client: client,
                    host: host,
                    outcome: .fallbackPlainShell(reason: .tmuxInstallerUnavailable)
                )
            }

            switch host.tmuxSetupConsent {
            case .unknown:
                return try await bootstrapPlainShell(
                    client: client,
                    host: host,
                    outcome: .fallbackPlainShell(
                        reason: .tmuxMissingConsentRequired(installCommand: installCommand)
                    )
                )
            case .declined:
                return try await bootstrapPlainShell(
                    client: client,
                    host: host,
                    outcome: .fallbackPlainShell(
                        reason: .tmuxMissingConsentDeclined(installCommand: installCommand)
                    )
                )
            case .approved:
                do {
                    let installResult = try await client.execute(command: installCommand)
                    if installResult.exitStatus != 0 {
                        return try await bootstrapPlainShell(
                            client: client,
                            host: host,
                            outcome: .fallbackPlainShell(
                                reason: .tmuxInstallFailed(
                                    installCommand: installCommand,
                                    details: Self.describe(installResult)
                                )
                            )
                        )
                    }

                    let postInstallAvailability: TmuxAvailability
                    do {
                        postInstallAvailability = try await detectTmuxAvailability(client: client)
                    } catch {
                        return try await bootstrapPlainShell(
                            client: client,
                            host: host,
                            outcome: .fallbackPlainShell(
                                reason: .tmuxInstallFailed(
                                    installCommand: installCommand,
                                    details: Self.truncated(error.localizedDescription)
                                )
                            )
                        )
                    }
                    switch postInstallAvailability {
                    case .available:
                        return try await bootstrapManagedTmuxLaunch(client: client, host: host)
                    case .missing:
                        return try await bootstrapPlainShell(
                            client: client,
                            host: host,
                            outcome: .fallbackPlainShell(
                                reason: .tmuxInstallFailed(
                                    installCommand: installCommand,
                                    details: "tmux is still unavailable after installation."
                                )
                            )
                        )
                    }
                } catch {
                    return try await bootstrapPlainShell(
                        client: client,
                        host: host,
                        outcome: .fallbackPlainShell(
                            reason: .tmuxInstallFailed(
                                installCommand: installCommand,
                                details: Self.truncated(error.localizedDescription)
                            )
                        )
                    )
                }
            }
        }
    }

    private func bootstrapManagedTmuxLaunch(
        client: SSHClient,
        host: HostProfile
    ) async throws -> MoshBootstrapResult {
        let command = ManagedRemoteCommandBuilder.managedTmuxLaunchCommand(for: host.id)
        let result = try await client.execute(command: command)

        do {
            let connectInfo = try Self.parseConnectInfo(from: result, serverAddress: host.hostname)
            return MoshBootstrapResult(connectInfo: connectInfo, persistenceOutcome: .managedTmuxActive)
        } catch let error as MoshBootstrapError {
            switch error {
            case .moshServerMissing, .nonUtf8Locale:
                throw error
            case .unexpectedOutput(let message):
                return try await bootstrapPlainShell(
                    client: client,
                    host: host,
                    outcome: .fallbackPlainShell(reason: .tmuxLaunchFailed(message: message))
                )
            }
        }
    }

    private func bootstrapPlainShell(
        client: SSHClient,
        host: HostProfile,
        outcome: PersistenceOutcome
    ) async throws -> MoshBootstrapResult {
        let result = try await client.execute(command: ManagedRemoteCommandBuilder.plainShellLaunchCommand)
        let connectInfo = try Self.parseConnectInfo(from: result, serverAddress: host.hostname)
        return MoshBootstrapResult(connectInfo: connectInfo, persistenceOutcome: outcome)
    }

    private func detectTmuxAvailability(client: SSHClient) async throws -> TmuxAvailability {
        let result = try await client.execute(command: ManagedRemoteCommandBuilder.tmuxPresenceCheckCommand)
        if result.exitStatus == 0 {
            return .available
        }
        let installCommand = try await detectTmuxInstallCommand(client: client)
        return .missing(installCommand: installCommand)
    }

    private func detectTmuxInstallCommand(client: SSHClient) async throws -> String? {
        let packageManagerResult = try await client.execute(command: ManagedRemoteCommandBuilder.packageManagerDetectionCommand)
        guard packageManagerResult.exitStatus == 0 else { return nil }

        let token = packageManagerResult.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard token != "none", let packageManager = ManagedRemotePackageManager(rawValue: token) else {
            return nil
        }

        if !packageManager.requiresPrivilegeEscalation {
            return packageManager.installTmuxCommand(useSudo: false)
        }

        let userIdResult = try await client.execute(command: ManagedRemoteCommandBuilder.currentUserIdCommand)
        let isRoot = userIdResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) == "0"
        return packageManager.installTmuxCommand(useSudo: !isRoot)
    }

    private static func describe(_ result: SSHCommandResult) -> String? {
        let output = [result.stderr, result.stdout]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return "exit status \(result.exitStatus)." }
        return truncated(output)
    }
}

extension MoshBootstrapper: MoshBootstrapping {}
