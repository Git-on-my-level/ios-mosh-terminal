import Foundation

// Phase-1 reintegration stub to satisfy prediction compilation.
// This will be replaced by the runtime-backed definition when we add MoshRuntime changes.
struct PredictionNetworkSnapshot: Sendable, Equatable {
    let lastSentStateNum: UInt64
    let lastAckedStateNum: UInt64
    let echoAck: UInt64
    let srttMillis: UInt64?
}

protocol PredictionNetworkSnapshotProviding: AnyObject, Sendable {
    func predictionNetworkSnapshot() -> PredictionNetworkSnapshot
}
