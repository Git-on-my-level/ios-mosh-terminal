import Foundation

private let udpHelpText = """
Mosh requires UDP for connection. Common causes:

• Captive portals (login screens on public Wi‑Fi)
• Enterprise Wi‑Fi or hotel networks
• Firewalls blocking UDP

Workarounds:

• Switch to a different network
• Use a VPN that allows UDP
• Connect via plain SSH instead
"""

struct ConnectionFailure: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let helpInfo: String?
    let allowsRetry: Bool
}

struct PersistenceWarning: Equatable {
    let title: String
    let message: String
    let actionTitle: String
    let installCommand: String?
}

enum ConnectionFailureReason: Error, Equatable {
    case udpUnreachable
    case udpTimeout
    case networkUnavailable
    case disconnected
}

struct ConnectionErrorMapper {
    static func map(
        error: Error,
        host: HostProfile?,
        networkSatisfied: Bool
    ) -> ConnectionFailure {
        if let reason = error as? ConnectionFailureReason {
            return map(reason: reason)
        }

        if let sshError = error as? SSHClientError {
            return map(sshError: sshError, networkSatisfied: networkSatisfied)
        }

        if let bootstrapError = error as? MoshBootstrapError {
            return map(bootstrapError: bootstrapError)
        }

        if let engineError = error as? MoshEngineError {
            return map(engineError: engineError)
        }

        if !networkSatisfied {
            return map(reason: .networkUnavailable)
        }

        let hostHint = host == nil ? "" : " Check the host and network and try again."
        return ConnectionFailure(
            title: "Connection failed",
            message: "Unable to connect.\(hostHint)",
            helpInfo: nil,
            allowsRetry: true
        )
    }

    static func mapPersistenceWarning(outcome: PersistenceOutcome?) -> PersistenceWarning? {
        guard case .fallbackPlainShell(let reason)? = outcome else { return nil }
        switch reason {
        case .hostPreferencePlainShell:
            return nil
        case .tmuxMissingConsentRequired(let installCommand):
            return PersistenceWarning(
                title: "Persistence unavailable",
                message: "tmux is missing on this host. Approve setup to enable managed persistence.",
                actionTitle: "Retry Setup",
                installCommand: installCommand
            )
        case .tmuxMissingConsentDeclined(let installCommand):
            return PersistenceWarning(
                title: "Persistence unavailable",
                message: "Managed persistence is currently disabled for this host. Retry setup to install tmux later.",
                actionTitle: "Retry Setup",
                installCommand: installCommand
            )
        case .tmuxInstallFailed(_, let details):
            let detailText: String
            if let details, !details.isEmpty {
                detailText = " \(details)"
            } else {
                detailText = ""
            }
            return PersistenceWarning(
                title: "Persistence unavailable",
                message: "tmux setup failed and this session is using a plain shell.\(detailText)",
                actionTitle: "Retry Setup",
                installCommand: reason.installCommand
            )
        case .tmuxInstallerUnavailable:
            return PersistenceWarning(
                title: "Persistence unavailable",
                message: "No supported package manager was detected. Install tmux manually and retry setup.",
                actionTitle: "Retry Setup",
                installCommand: nil
            )
        case .tmuxLaunchFailed(let message):
            return PersistenceWarning(
                title: "Persistence unavailable",
                message: "tmux setup failed (\(message)). Connected with a plain shell.",
                actionTitle: "Retry Setup",
                installCommand: nil
            )
        }
    }

    private static func map(reason: ConnectionFailureReason) -> ConnectionFailure {
        switch reason {
        case .udpUnreachable:
            return ConnectionFailure(
                title: "UDP blocked",
                message: "This network appears to block UDP. Mosh requires UDP.",
                helpInfo: udpHelpText,
                allowsRetry: true
            )
        case .udpTimeout:
            return ConnectionFailure(
                title: "UDP timeout",
                message: "No UDP response was received. UDP may be blocked on this network.",
                helpInfo: udpHelpText,
                allowsRetry: true
            )
        case .networkUnavailable:
            return ConnectionFailure(
                title: "Network unavailable",
                message: "Check your connection and try again.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .disconnected:
            return ConnectionFailure(
                title: "Disconnected",
                message: "Connection dropped. We'll retry when the network returns.",
                helpInfo: nil,
                allowsRetry: true
            )
        }
    }

    private static func map(
        sshError: SSHClientError,
        networkSatisfied: Bool
    ) -> ConnectionFailure {
        switch sshError {
        case .authenticationFailed:
            return ConnectionFailure(
                title: "Authentication failed",
                message: "Check that your SSH key is authorized on the host and the passphrase is correct.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .hostKeyMismatch:
            return ConnectionFailure(
                title: "Host key changed",
                message: "The host key doesn't match the saved one. Verify the server identity, then remove and re-add this host to trust the new key.",
                helpInfo: nil,
                allowsRetry: false
            )
        case .hostKeyUntrusted:
            return ConnectionFailure(
                title: "Host key not trusted",
                message: "Retry and accept the host key if you trust this server.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .connectionFailed(let message):
            let lowercased = message.lowercased()
            if !networkSatisfied
                || lowercased.contains("resolve host")
                || lowercased.contains("unable to connect") {
                return map(reason: .networkUnavailable)
            }
            return ConnectionFailure(
                title: "SSH connection failed",
                message: "Check the host address, port, and network, then try again.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .commandFailed:
            return ConnectionFailure(
                title: "SSH command failed",
                message: "Unable to start mosh-server over SSH. Ensure mosh-server is installed and retry.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .storageFailure:
            return ConnectionFailure(
                title: "Host key storage error",
                message: "Unable to access trusted host key storage.",
                helpInfo: nil,
                allowsRetry: false
            )
        case .libraryUnavailable:
            return ConnectionFailure(
                title: "SSH unavailable",
                message: "SSH support is unavailable in this build.",
                helpInfo: nil,
                allowsRetry: false
            )
        case .notConnected, .alreadyConnected, .cancelled:
            return ConnectionFailure(
                title: "SSH unavailable",
                message: "SSH session is not available. Try again.",
                helpInfo: nil,
                allowsRetry: true
            )
        }
    }

    private static func map(bootstrapError: MoshBootstrapError) -> ConnectionFailure {
        switch bootstrapError {
        case .moshServerMissing:
            return ConnectionFailure(
                title: "mosh-server missing",
                message: "mosh-server was not found on the host. Install it and retry.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .nonUtf8Locale:
            return ConnectionFailure(
                title: "Locale required",
                message: "mosh-server requires a UTF-8 locale on the host. Configure a UTF-8 locale and retry.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .unexpectedOutput:
            return ConnectionFailure(
                title: "mosh-server error",
                message: "Unexpected response while starting mosh-server. Verify the host setup and retry.",
                helpInfo: nil,
                allowsRetry: true
            )
        }
    }

    private static func map(engineError: MoshEngineError) -> ConnectionFailure {
        switch engineError {
        case .libraryUnavailable:
            return ConnectionFailure(
                title: "Mosh unavailable",
                message: "Mosh client support is unavailable in this build.",
                helpInfo: nil,
                allowsRetry: false
            )
        case .startFailed:
            return ConnectionFailure(
                title: "Mosh start failed",
                message: "Unable to start the Mosh client. Check your network and retry.",
                helpInfo: nil,
                allowsRetry: true
            )
        case .udpUnreachable:
            return map(reason: .udpUnreachable)
        case .integrityFailure:
            return ConnectionFailure(
                title: "Connection unstable",
                message: "Too many invalid packets were received. Check the network and retry.",
                helpInfo: nil,
                allowsRetry: true
            )
        }
    }
}

private extension PersistenceFallbackReason {
    var installCommand: String? {
        switch self {
        case .tmuxMissingConsentRequired(let installCommand),
             .tmuxMissingConsentDeclined(let installCommand),
             .tmuxInstallFailed(let installCommand, _):
            return installCommand
        case .hostPreferencePlainShell, .tmuxInstallerUnavailable, .tmuxLaunchFailed:
            return nil
        }
    }
}
