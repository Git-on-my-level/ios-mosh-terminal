import Foundation
import SwiftTerm

final class TerminalPredictionCoordinator {
    private let engine = PredictionEngine()

    weak var terminalView: TerminalUIKitView?
    weak var overlayView: PredictionOverlayView?
    weak var predictionNetworkProvider: PredictionNetworkSnapshotProviding?

    init() {}

    func setDisplayPreference(_ preference: PredictionDisplayPreference) {
        engine.displayPreference = preference
    }

    func reset() {
        engine.reset()
        updateOverlayWithEmpty()
    }

    func handleUserInput(data: Data) {
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis)

            let visibleModel = engine.currentRenderModel(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
            let displayGrid = PredictedDisplayGrid(confirmedGrid: confirmedGrid, renderModel: visibleModel)

            engine.newUserBytes(data, displayGrid: displayGrid, nowMillis: nowMillis)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    func handleConfirmedOutputApplied() {
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    func handleResize(cols: Int, rows: Int) {
        engine.reset()
        updateOverlayWithEmpty()
    }

    func handleEchoAckUpdated() {
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    private func withConfirmedGrid(_ block: @escaping (SwiftTermConfirmedGrid, Int64) -> Void) {
        guard let terminalView else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.withConfirmedGrid(block)
            }
            return
        }
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
