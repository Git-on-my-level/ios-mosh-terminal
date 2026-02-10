import Foundation
import MoshClientCore
import SwiftTerm
import UIKit

@MainActor
public final class TerminalPredictionCoordinator {
    private let engine = PredictionEngine()

    public weak var terminalView: SwiftTerm.TerminalView?
    public weak var overlayView: PredictionOverlayView?
    public weak var predictionNetworkProvider: PredictionNetworkSnapshotProviding?

    private var isNativeCaretSuppressed = false
    private var savedCaretColor: UIColor?
    private var savedCaretTextColor: UIColor?

    public init() {}

    public func setDisplayPreference(_ preference: PredictionDisplayPreference) {
        engine.displayPreference = preference
        if preference == .off {
            engine.reset()
            updateOverlayWithEmpty()
        }
    }

    public func debugSnapshot() -> PredictionDebugMetrics {
        updateNetworkSnapshot()
        return engine.debugMetrics
    }

    public func reset() {
        engine.reset()
        updateOverlayWithEmpty()
    }

    public func handleUserInput(data: Data) {
        if engine.displayPreference == .off {
            updateOverlayWithEmpty()
            return
        }
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis, didReceiveOutput: false)

            // Use the full prediction state for subsequent keystroke prediction, even if we're
            // intentionally hiding tentative predictions from the UI via epoch gating.
            let predictionStateModel = engine.currentPredictionStateModel()
            let displayGrid = PredictedDisplayGrid(confirmedGrid: confirmedGrid, renderModel: predictionStateModel)

            engine.newUserBytes(data, displayGrid: displayGrid, nowMillis: nowMillis)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    public func handleConfirmedOutputApplied() {
        if engine.displayPreference == .off {
            updateOverlayWithEmpty()
            return
        }
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis, didReceiveOutput: true)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    public func handleResize(cols: Int, rows: Int) {
        if engine.displayPreference == .off {
            updateOverlayWithEmpty()
            return
        }
        // Resizes are common on iOS (rotation, keyboard show/hide, split view). Resetting here
        // makes in-flight predicted input "disappear", which feels like input loss. Instead,
        // keep state and let the engine cull/adjust against the current confirmed grid.
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis, didReceiveOutput: false)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    public func handleEchoAckUpdated() {
        if engine.displayPreference == .off {
            updateOverlayWithEmpty()
            return
        }
        withConfirmedGrid { [self] confirmedGrid, nowMillis in
            updateNetworkSnapshot()
            engine.cull(confirmedGrid: confirmedGrid, nowMillis: nowMillis, didReceiveOutput: false)
            updateOverlay(confirmedGrid: confirmedGrid, nowMillis: nowMillis)
        }
    }

    private func withConfirmedGrid(_ block: @escaping (SwiftTermConfirmedGrid, Int64) -> Void) {
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
        if let terminalView = terminalView, overlayView.superview === terminalView {
            // SwiftTerm's TerminalView is a UIScrollView and changes its bounds origin as it scrolls.
            // Keep the overlay pinned to the visible region so predictions don't "fall off" after output scrolls.
            //
            // Symptoms when this is wrong:
            // - predictions appear to stop after a command outputs/scrolls
            // - typed characters can show up in the top-left or other incorrect positions
            if overlayView.frame != terminalView.bounds {
                overlayView.frame = terminalView.bounds
            }
        }
        overlayView.model = model
        updateNativeCaretSuppression(suppress: suppressNativeCaret)
        if let terminalView = terminalView, overlayView.superview === terminalView {
            terminalView.bringSubviewToFront(overlayView)
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
