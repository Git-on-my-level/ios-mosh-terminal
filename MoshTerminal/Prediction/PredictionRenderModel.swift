import Foundation

struct PredictionRenderModel: Equatable {
    var overlayRows: [OverlayRowState]
    var cursorPredictions: [CursorPrediction]
    var showPredictions: Bool
    var underlinePredictions: Bool

    init(
        overlayRows: [OverlayRowState] = [],
        cursorPredictions: [CursorPrediction] = [],
        showPredictions: Bool = false,
        underlinePredictions: Bool = false
    ) {
        self.overlayRows = overlayRows
        self.cursorPredictions = cursorPredictions
        self.showPredictions = showPredictions
        self.underlinePredictions = underlinePredictions
    }
}
