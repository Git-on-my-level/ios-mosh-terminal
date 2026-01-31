import Foundation
import SwiftTerm

final class TerminalPredictionCoordinator {
    private let engine = PredictionEngine()

    weak var terminalView: TerminalUIKitView?
    weak var overlayView: PredictionOverlayView?
    weak var predictionNetworkProvider: PredictionNetworkSnapshotProviding?

    init() {}

    func reset() {
        engine.reset()
        updateOverlayWithEmpty()
    }

    func handleUserInput(data: Data) {
        withConfirmedGrid { confirmedGrid, nowMillis in
            updateNetworkSnapshot()

            let visibleModel = engine.currentRenderModel(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
            let displayGrid = PredictedDisplayGrid(confirmedGrid: confirmedGrid, renderModel: visibleModel)

            engine.newUserBytes(data, displayGrid: displayGrid, nowMillis: nowMillis)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    func handleConfirmedOutputApplied() {
        withConfirmedGrid { confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    func handleResize(cols: Int, rows: Int) {
        engine.reset()
        updateOverlayWithEmpty()
    }

    func handleEchoAckUpdated() {
        withConfirmedGrid { confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    private func withConfirmedGrid(_ block: (SwiftTermConfirmedGrid, Int64) -> Void) {
        guard let terminalView else { return }
        let terminal = terminalView.getTerminal()
        let grid = SwiftTermConfirmedGrid(terminal: terminal)
        let nowMillis = Int64(Clock.nowMillis())
        block(grid, nowMillis)
    }

    private func updateNetworkSnapshot() {
        if let snapshot = predictionNetworkProvider?.predictionNetworkSnapshot() {
            engine.updateNetworkSnapshot(snapshot)
        }
    }

    private func updateOverlay(confirmedGrid: DisplayGrid, nowMillis: Int64) {
        engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        let renderModel = engine.currentRenderModel(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        updateOverlayView(renderModel)
    }

    private func updateOverlayWithEmpty() {
        updateOverlayView(PredictionRenderModel())
    }

    private func updateOverlayView(_ model: PredictionRenderModel) {
        guard let overlayView else { return }
        if Thread.isMainThread {
            overlayView.model = model
        } else {
            DispatchQueue.main.async {
                overlayView.model = model
            }
        }
    }
}
