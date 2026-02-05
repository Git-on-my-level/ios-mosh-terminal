import Foundation
import SwiftTerm
import UIKit

final class TerminalPredictionCoordinator {
    private let engine = PredictionEngine()

    weak var terminalView: TerminalUIKitView?
    weak var overlayView: PredictionOverlayView?
    weak var predictionNetworkProvider: PredictionNetworkSnapshotProviding?

    private var isNativeCaretSuppressed = false
    private var savedCaretColor: UIColor?
    private var savedCaretTextColor: UIColor?

    init() {}

    func setDisplayPreference(_ preference: PredictionDisplayPreference) {
        engine.displayPreference = preference
    }

    func debugSnapshot() -> PredictionDebugMetrics {
        updateNetworkSnapshot()
        return engine.debugMetrics
    }

    func reset() {
        engine.reset()
        updateOverlayWithEmpty()
    }

    func handleUserInput(data: Data) {
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis)

            // Use the full prediction state for subsequent keystroke prediction, even if we're
            // intentionally hiding tentative predictions from the UI via epoch gating.
            let predictionStateModel = engine.currentPredictionStateModel()
            let displayGrid = PredictedDisplayGrid(confirmedGrid: confirmedGrid, renderModel: predictionStateModel)

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
        let suppressNativeCaret = shouldSuppressNativeCaret(renderModel: renderModel, confirmedGrid: confirmedGrid)
        updateOverlayView(renderModel, suppressNativeCaret: suppressNativeCaret)
    }

    private func updateOverlayWithEmpty() {
        updateOverlayView(PredictionRenderModel(), suppressNativeCaret: false)
    }

    private func shouldSuppressNativeCaret(renderModel: PredictionRenderModel, confirmedGrid: DisplayGrid) -> Bool {
        guard renderModel.showPredictions else { return false }
        guard let predictedCursor = renderModel.cursorPredictions.last else { return false }
        return predictedCursor.row != confirmedGrid.cursorRow || predictedCursor.col != confirmedGrid.cursorCol
    }

    private func updateOverlayView(_ model: PredictionRenderModel, suppressNativeCaret: Bool) {
        guard let overlayView else { return }
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            overlayView.model = model
            self.updateNativeCaretSuppression(suppress: suppressNativeCaret)
            if let terminalView = self.terminalView, overlayView.superview === terminalView {
                terminalView.bringSubviewToFront(overlayView)
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func updateNativeCaretSuppression(suppress: Bool) {
        guard let terminalView else { return }

        if suppress {
            if isNativeCaretSuppressed {
                return
            }
            savedCaretColor = terminalView.caretColor
            savedCaretTextColor = terminalView.caretTextColor
            terminalView.caretColor = .clear
            terminalView.caretTextColor = .clear
            isNativeCaretSuppressed = true
            return
        }

        guard isNativeCaretSuppressed else { return }
        if let savedCaretColor {
            terminalView.caretColor = savedCaretColor
        }
        terminalView.caretTextColor = savedCaretTextColor
        savedCaretColor = nil
        savedCaretTextColor = nil
        isNativeCaretSuppressed = false
    }
}
