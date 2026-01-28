import Foundation

enum TransportReceiveError: Error, Equatable {
    case invalidProtocolVersion(expected: UInt32, actual: UInt32)
}

struct RemoteStateTracker: Equatable {
    private(set) var lastAppliedRemoteNum: UInt64 = 0

    func canApply(_ instruction: TransportInstruction) -> Bool {
        instruction.oldNum == lastAppliedRemoteNum
    }

    mutating func didApply(newNum: UInt64) {
        lastAppliedRemoteNum = newNum
    }
}

struct HostDiffApplier {
    var onTerminalOutput: (Data) -> Void
    var onResize: (Int, Int) -> Void
    var onEchoAck: ((UInt64) -> Void)?

    func apply(hostEvents: [HostEvent]) {
        for event in hostEvents {
            switch event {
            case .hostBytes(let data):
                onTerminalOutput(data)
            case .resize(let cols, let rows):
                onResize(cols, rows)
            case .echoAck(let value):
                onEchoAck?(value)
            }
        }
    }
}

final class TransportReceiver {
    private let expectedProtocolVersion: UInt32 = 2
    private let transportSender: TransportSender
    private let hostApplier: HostDiffApplier
    private let onDisconnect: (() -> Void)?

    private(set) var remoteStateTracker: RemoteStateTracker

    init(transportSender: TransportSender,
         remoteStateTracker: RemoteStateTracker = RemoteStateTracker(),
         hostApplier: HostDiffApplier,
         onDisconnect: (() -> Void)? = nil) {
        self.transportSender = transportSender
        self.remoteStateTracker = remoteStateTracker
        self.hostApplier = hostApplier
        self.onDisconnect = onDisconnect
    }

    func process(_ instruction: TransportInstruction) throws {
        guard instruction.protocolVersion == expectedProtocolVersion else {
            throw TransportReceiveError.invalidProtocolVersion(
                expected: expectedProtocolVersion,
                actual: instruction.protocolVersion
            )
        }

        transportSender.processAckThrough(instruction.ackNum)

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
