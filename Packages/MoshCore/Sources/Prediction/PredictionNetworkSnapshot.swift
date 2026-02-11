import Foundation

public struct PredictionNetworkSnapshot: Sendable, Equatable {
    public let lastSentStateNum: UInt64
    public let lastAckedStateNum: UInt64
    public let echoAck: UInt64
    public let srttMillis: UInt64?

    public init(lastSentStateNum: UInt64, lastAckedStateNum: UInt64, echoAck: UInt64, srttMillis: UInt64?) {
        self.lastSentStateNum = lastSentStateNum
        self.lastAckedStateNum = lastAckedStateNum
        self.echoAck = echoAck
        self.srttMillis = srttMillis
    }
}

public protocol PredictionNetworkSnapshotProviding: AnyObject, Sendable {
    func predictionNetworkSnapshot() -> PredictionNetworkSnapshot
}
