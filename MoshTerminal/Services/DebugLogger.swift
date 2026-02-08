#if DEBUG
import os

protocol DebugLogProviding: Sendable {
    var isEnabled: Bool { get }
    func logConnectionEvent(_ event: ConnectionDebugEvent)
    func logTransportEvent(_ event: TransportDebugEvent)
    func logLivenessEvent(_ event: LivenessDebugEvent)
    func logPredictionEvent(_ event: PredictionDebugEvent)
}

final class DebugLogger: DebugLogProviding {
    static let shared = DebugLogger()

    private let logger: Logger
    private let subsystem = "com.moshterminal"

    var isEnabled: Bool {
        didSet {
            if isEnabled {
                logger.log(level: .info, "Debug logging enabled")
            }
        }
    }

    init() {
        self.logger = Logger(subsystem: subsystem, category: "Connection")
        self.isEnabled = false
    }

    func logConnectionEvent(_ event: ConnectionDebugEvent) {
        guard isEnabled else { return }
        logger.info("\(event.description, privacy: .public)")
    }

    func logTransportEvent(_ event: TransportDebugEvent) {
        guard isEnabled else { return }
        logger.info("\(event.description, privacy: .public)")
    }

    func logLivenessEvent(_ event: LivenessDebugEvent) {
        guard isEnabled else { return }
        logger.info("\(event.description, privacy: .public)")
    }

    func logPredictionEvent(_ event: PredictionDebugEvent) {
        guard isEnabled else { return }
        logger.info("\(event.description, privacy: .public)")
    }
}

struct ConnectionDebugEvent: Sendable {
    enum Kind: Sendable {
        case stateTransition(from: String, to: String)
        case startAttempt(isReconnect: Bool, hostId: String)
        case reconnectRequest(reason: String)
        case backoffApplied(delaySeconds: Double)
        case sshBootstrap(success: Bool, errorDescription: String?)
        case udpConnect(success: Bool, timeoutMillis: UInt64?)
        case engineAttached
        case engineDetached
        case failure(title: String, errorDescription: String)
        case idleSessionStart(isReconnect: Bool)
        case idleSessionEnd
    }

    let kind: Kind
    let timestamp: UInt64

    var description: String {
        let timestampStr = formatTimestamp(timestamp)
        switch kind {
        case .stateTransition(let from, let to):
            return "[\(timestampStr)] State transition: \(from) -> \(to)"
        case .startAttempt(let isReconnect, let hostId):
            return "[\(timestampStr)] Start attempt (reconnect: \(isReconnect), hostId: \(redactUUID(hostId)))"
        case .reconnectRequest(let reason):
            return "[\(timestampStr)] Reconnect requested: \(reason)"
        case .backoffApplied(let delaySeconds):
            return "[\(timestampStr)] Backoff applied: \(String(format: "%.1f", delaySeconds))s"
        case .sshBootstrap(let success, let errorDesc):
            if success {
                return "[\(timestampStr)] SSH bootstrap succeeded"
            } else {
                return "[\(timestampStr)] SSH bootstrap failed: \(errorDesc ?? "unknown")"
            }
        case .udpConnect(let success, let timeout):
            if success {
                return "[\(timestampStr)] UDP connect succeeded"
            } else if let timeout {
                return "[\(timestampStr)] UDP connect timed out (\(timeout)ms)"
            } else {
                return "[\(timestampStr)] UDP connect failed"
            }
        case .engineAttached:
            return "[\(timestampStr)] Engine attached"
        case .engineDetached:
            return "[\(timestampStr)] Engine detached"
        case .failure(let title, let errorDesc):
            return "[\(timestampStr)] Failure: \(title) - \(errorDesc)"
        case .idleSessionStart(let isReconnect):
            return "[\(timestampStr)] Idle session started (reconnect: \(isReconnect))"
        case .idleSessionEnd:
            return "[\(timestampStr)] Idle session ended"
        }
    }

    private func redactUUID(_ uuid: String) -> String {
        let str = uuid.replacingOccurrences(of: "-", with: "")
        guard str.count >= 8 else { return "[REDACTED]" }
        return String(str.prefix(8)) + "..."
    }

    private func formatTimestamp(_ millis: UInt64) -> String {
        let seconds = millis / 1000
        let remainder = millis % 1000
        return String(format: "%06d.%03d", seconds, remainder)
    }
}

struct TransportDebugEvent: Sendable {
    enum Kind: Sendable {
        case socketOpened(localPort: UInt16)
        case portHop(from: UInt16, to: UInt16)
        case socketClosed(localPort: UInt16)
        case sendError(errno: Int32)
        case connectAttempt(host: String, port: UInt16)
        case roundtripSuccess
    }

    let kind: Kind
    let timestamp: UInt64

    var description: String {
        let timestampStr = formatTimestamp(timestamp)
        switch kind {
        case .socketOpened(let port):
            return "[\(timestampStr)] Socket opened on port \(port)"
        case .portHop(let from, let to):
            return "[\(timestampStr)] Port hop: \(from) -> \(to)"
        case .socketClosed(let port):
            return "[\(timestampStr)] Socket closed (port \(port))"
        case .sendError(let errno):
            return "[\(timestampStr)] Send error (errno: \(errno))"
        case .connectAttempt(let host, let port):
            return "[\(timestampStr)] Connect attempt: \(host):\(port)"
        case .roundtripSuccess:
            return "[\(timestampStr)] Roundtrip success"
        }
    }

    private func formatTimestamp(_ millis: UInt64) -> String {
        let seconds = millis / 1000
        let remainder = millis % 1000
        return String(format: "%06d.%03d", seconds, remainder)
    }
}

struct LivenessDebugEvent: Sendable {
    enum Kind: Sendable {
        case connected
        case disconnected(reason: String)
        case failed(error: String)
        case livenessCheck(lastHeardAge: UInt64, consecutiveUnreachable: Int)
        case keepaliveSent
        case corruptPacket(consecutiveCount: Int)
        case unreachableSend(consecutiveCount: Int)
    }

    let kind: Kind
    let timestamp: UInt64

    var description: String {
        let timestampStr = formatTimestamp(timestamp)
        switch kind {
        case .connected:
            return "[\(timestampStr)] Connected"
        case .disconnected(let reason):
            return "[\(timestampStr)] Disconnected: \(reason)"
        case .failed(let error):
            return "[\(timestampStr)] Failed: \(error)"
        case .livenessCheck(let age, let unreachable):
            return "[\(timestampStr)] Liveness check (lastHeard: \(age)ms, unreachable: \(unreachable))"
        case .keepaliveSent:
            return "[\(timestampStr)] Keepalive sent"
        case .corruptPacket(let count):
            return "[\(timestampStr)] Corrupt packet (consecutive: \(count))"
        case .unreachableSend(let count):
            return "[\(timestampStr)] Unreachable send (consecutive: \(count))"
        }
    }

    private func formatTimestamp(_ millis: UInt64) -> String {
        let seconds = millis / 1000
        let remainder = millis % 1000
        return String(format: "%06d.%03d", seconds, remainder)
    }
}

struct PredictionDebugEvent: Sendable {
    enum Kind: Sendable {
        case echoAckUpdate(value: UInt64)
        case networkSnapshot(
            lastSentStateNum: UInt64,
            lastAckedStateNum: UInt64,
            echoAck: UInt64,
            srttMillis: UInt64?
        )
    }

    let kind: Kind
    let timestamp: UInt64

    var description: String {
        let timestampStr = formatTimestamp(timestamp)
        switch kind {
        case .echoAckUpdate(let value):
            return "[\(timestampStr)] Echo ack updated: \(value)"
        case .networkSnapshot(let sent, let acked, let echo, let srtt):
            let srttStr = srtt.map { "\($0)ms" } ?? "nil"
            return "[\(timestampStr)] Network snapshot: sent=\(sent), acked=\(acked), echoAck=\(echo), srtt=\(srttStr)"
        }
    }

    private func formatTimestamp(_ millis: UInt64) -> String {
        let seconds = millis / 1000
        let remainder = millis % 1000
        return String(format: "%06d.%03d", seconds, remainder)
    }
}

extension ConnectionManager.State {
    var debugName: String {
        switch self {
        case .idle:
            return "idle"
        case .disconnected:
            return "disconnected"
        case .bootstrappingSSH:
            return "bootstrappingSSH"
        case .connectingUDP:
            return "connectingUDP"
        case .connected:
            return "connected"
        case .reconnecting:
            return "reconnecting"
        case .failed:
            return "failed"
        }
    }
}
#endif
