import Foundation

struct ConnectionFailure: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let allowsRetry: Bool
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
            allowsRetry: true
        )
    }

    private static func map(reason: ConnectionFailureReason) -> ConnectionFailure {
        switch reason {
        case .udpUnreachable:
            return ConnectionFailure(
                title: "UDP blocked",
                message: "This network appears to block UDP. Mosh requires UDP.",
                allowsRetry: true
            )
        case .udpTimeout:
            return ConnectionFailure(
                title: "UDP timeout",
                message: "No UDP response was received yet. This can happen on slow or lossy networks. Try again.",
                allowsRetry: true
            )
        case .networkUnavailable:
            return ConnectionFailure(
                title: "Network unavailable",
                message: "Check your connection and try again.",
                allowsRetry: true
            )
        case .disconnected:
            return ConnectionFailure(
                title: "Disconnected",
                message: "Connection dropped. We'll retry when the network returns.",
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
                allowsRetry: true
            )
        case .hostKeyMismatch:
            return ConnectionFailure(
                title: "Host key changed",
                message: "The host key doesn't match the saved one. Verify the server identity, then remove and re-add this host to trust the new key.",
                allowsRetry: false
            )
        case .hostKeyUntrusted:
            return ConnectionFailure(
                title: "Host key not trusted",
                message: "Retry and accept the host key if you trust this server.",
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
                allowsRetry: true
            )
        case .commandFailed:
            return ConnectionFailure(
                title: "SSH command failed",
                message: "Unable to start mosh-server over SSH. Ensure mosh-server is installed and retry.",
                allowsRetry: true
            )
        case .storageFailure:
            return ConnectionFailure(
                title: "Host key storage error",
                message: "Unable to access trusted host key storage.",
                allowsRetry: false
            )
        case .libraryUnavailable:
            return ConnectionFailure(
                title: "SSH unavailable",
                message: "SSH support is unavailable in this build.",
                allowsRetry: false
            )
        case .notConnected, .alreadyConnected, .cancelled:
            return ConnectionFailure(
                title: "SSH unavailable",
                message: "SSH session is not available. Try again.",
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
                allowsRetry: true
            )
        case .nonUtf8Locale:
            return ConnectionFailure(
                title: "Locale required",
                message: "mosh-server requires a UTF-8 locale on the host. Configure a UTF-8 locale and retry.",
                allowsRetry: true
            )
        case .unexpectedOutput:
            return ConnectionFailure(
                title: "mosh-server error",
                message: "Unexpected response while starting mosh-server. Verify the host setup and retry.",
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
                allowsRetry: false
            )
        case .startFailed:
            return ConnectionFailure(
                title: "Mosh start failed",
                message: "Unable to start the Mosh client. Check your network and retry.",
                allowsRetry: true
            )
        case .udpUnreachable:
            return map(reason: .udpUnreachable)
        case .integrityFailure:
            return ConnectionFailure(
                title: "Connection unstable",
                message: "Too many invalid packets were received. Check the network and retry.",
                allowsRetry: true
            )
        }
    }
}
