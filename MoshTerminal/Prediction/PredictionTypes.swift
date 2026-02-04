import Foundation

struct DisplayCell: Equatable {
    let char: Character
    let width: Int

    static let blank = DisplayCell(char: " ", width: 1)
}

protocol DisplayGrid {
    var cols: Int { get }
    var rows: Int { get }
    var cursorRow: Int { get }
    var cursorCol: Int { get }
    var isInsertMode: Bool { get }
    func cell(atRow row: Int, col: Int) -> DisplayCell
}

extension DisplayGrid {
    var isInsertMode: Bool { false }
}

struct OverlayCellState: Equatable {
    var active: Bool
    var col: Int
    var replacement: DisplayCell?
    var unknown: Bool
    var originalContents: [DisplayCell]
    var expirationFrame: Int64
    var predictionTime: Int64
    var tentativeUntilEpoch: Int
}

struct OverlayRowState: Equatable {
    var unknownRow: Bool
    var cells: [OverlayCellState]
}

struct CursorPrediction: Equatable {
    var row: Int
    var col: Int
    var expirationFrame: Int64
    var predictionTime: Int64
    var tentativeUntilEpoch: Int
}

struct CellPosition: Hashable {
    let row: Int
    let col: Int
}

struct PredictionDebugState: Equatable {
    var overlayRows: [OverlayRowState]
    var cursorPredictions: [CursorPrediction]
    var predictionEpoch: Int
    var confirmedEpoch: Int
    var predictedCursorRow: Int
    var predictedCursorCol: Int
    var cols: Int
    var rows: Int
}

struct PredictionDebugMetrics: Equatable {
    var sendIntervalMillis: Int64
    var echoAck: Int64
    var glitchTrigger: Int
    var srttTrigger: Bool
    var activePredictionCount: Int
}
