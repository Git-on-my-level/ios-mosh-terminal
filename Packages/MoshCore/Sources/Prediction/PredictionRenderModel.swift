import Foundation

public struct PredictionRenderModel: Equatable {
    public var overlayRows: [OverlayRowState]
    public var cursorPredictions: [CursorPrediction]
    public var showPredictions: Bool
    public var underlinePredictions: Bool

    public init(
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
