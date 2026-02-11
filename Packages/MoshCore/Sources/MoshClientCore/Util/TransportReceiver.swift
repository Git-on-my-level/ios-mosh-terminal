import Foundation

public enum TransportReceiveError: Error, Equatable {
    case invalidProtocolVersion(expected: UInt32, actual: UInt32)
}

public struct RemoteStateTracker: Equatable {
    private(set) var lastAppliedRemoteNum: UInt64 = 0

    public init() {}

    public func canApply(_ instruction: TransportInstruction) -> Bool {
        instruction.oldNum == lastAppliedRemoteNum
    }

    public mutating func didApply(newNum: UInt64) {
        lastAppliedRemoteNum = newNum
    }
}

public struct HostDiffApplier {
    public var onTerminalOutput: (Data) -> Void
    public var onResize: (Int, Int) -> Void
    public var onEchoAckUpdate: ((UInt64) -> Void)?
    public var onEchoAckStandalone: ((UInt64) -> Void)?

    public init(
        onTerminalOutput: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        onEchoAckUpdate: ((UInt64) -> Void)? = nil,
        onEchoAckStandalone: ((UInt64) -> Void)? = nil
    ) {
        self.onTerminalOutput = onTerminalOutput
        self.onResize = onResize
        self.onEchoAckUpdate = onEchoAckUpdate
        self.onEchoAckStandalone = onEchoAckStandalone
    }

    func apply(hostEvents: [HostEvent]) {
        guard !hostEvents.isEmpty else { return }

        var lastEchoAck: UInt64?
        var hasOutputOrResize = false

        for event in hostEvents {
            switch event {
            case .hostBytes:
                hasOutputOrResize = true
            case .resize:
                hasOutputOrResize = true
            case .echoAck(let value):
                lastEchoAck = value
            }
        }

        if let lastEchoAck {
            onEchoAckUpdate?(lastEchoAck)
        }

        for event in hostEvents {
            switch event {
            case .hostBytes(let data):
                onTerminalOutput(data)
            case .resize(let cols, let rows):
                onResize(cols, rows)
            case .echoAck:
                break
            }
        }

        if !hasOutputOrResize, let lastEchoAck {
            onEchoAckStandalone?(lastEchoAck)
        }
    }
}

public final class TransportReceiver {
    private let expectedProtocolVersion: UInt32 = 2
    private let transportSender: TransportSender
    private let hostApplier: HostDiffApplier
    private let onDisconnect: (() -> Void)?

    public private(set) var remoteStateTracker: RemoteStateTracker

    public init(transportSender: TransportSender,
                remoteStateTracker: RemoteStateTracker = RemoteStateTracker(),
                hostApplier: HostDiffApplier,
                onDisconnect: (() -> Void)? = nil) {
        self.transportSender = transportSender
        self.remoteStateTracker = remoteStateTracker
        self.hostApplier = hostApplier
        self.onDisconnect = onDisconnect
    }

    public func process(_ instruction: TransportInstruction, nowMillis: UInt64) throws {
        guard instruction.protocolVersion == expectedProtocolVersion else {
            throw TransportReceiveError.invalidProtocolVersion(
                expected: expectedProtocolVersion,
                actual: instruction.protocolVersion
            )
        }

        transportSender.processAckThrough(instruction.ackNum, nowMillis: nowMillis)

        if instruction.newNum == UInt64.max {
            onDisconnect?()
            return
        }

        guard !instruction.diff.isEmpty else {
            return
        }

        guard remoteStateTracker.canApply(instruction) else {
            return
        }

        let events = try HostMessageCodec.decode(data: instruction.diff)
        hostApplier.apply(hostEvents: events)
        remoteStateTracker.didApply(newNum: instruction.newNum)
        transportSender.setAckNum(remoteStateTracker.lastAppliedRemoteNum)
    }
}
