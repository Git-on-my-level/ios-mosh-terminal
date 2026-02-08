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
    ) async throws -> MoshConnectInfo {
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

        let result = try await client.execute(command: "mosh-server new")
        return try Self.parseConnectInfo(from: result, serverAddress: host.hostname)
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
}

extension MoshBootstrapper: MoshBootstrapping {}
