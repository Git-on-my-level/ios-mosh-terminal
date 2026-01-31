import Foundation

final class PredictionEngine {
    func reset() {
    }

    func updateNetworkSnapshot(_ snapshot: PredictionNetworkSnapshot) {
    }

    func newUserBytes(_ bytes: Data, displayGrid: Any, nowMillis: Int64) {
    }

    func cull(confirmedGrid: Any, nowMillis: Int64) {
    }

    func currentRenderModel(confirmedGrid: Any, nowMillis: Int64) -> PredictionRenderModel {
        return PredictionRenderModel()
    }
}
