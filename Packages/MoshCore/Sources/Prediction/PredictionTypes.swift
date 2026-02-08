import Foundation

public struct DisplayCell: Equatable, Sendable {
    public let char: Character
    public let width: Int

    public static let blank = DisplayCell(char: " ", width: 1)
}

public protocol DisplayGrid {
    var cols: Int { get }
    var rows: Int { get }
    var cursorRow: Int { get }
    var cursorCol: Int { get }
    var isInsertMode: Bool { get }
    func cell(atRow row: Int, col: Int) -> DisplayCell
}

extension DisplayGrid {
    public var isInsertMode: Bool { false }
}

public struct OverlayCellState: Equatable {
    public var active: Bool
    public var col: Int
    public var replacement: DisplayCell?
    public var unknown: Bool
    public var originalContents: [DisplayCell]
    public var expirationFrame: Int64
    public var predictionTime: Int64
    public var tentativeUntilEpoch: Int
}

public struct OverlayRowState: Equatable {
    public var unknownRow: Bool
    public var cells: [OverlayCellState]
}

public struct CursorPrediction: Equatable {
    public var row: Int
    public var col: Int
    public var expirationFrame: Int64
    public var predictionTime: Int64
    public var tentativeUntilEpoch: Int
}

public struct CellPosition: Hashable {
    public let row: Int
    public let col: Int
}

public struct PredictionDebugState: Equatable {
    public var overlayRows: [OverlayRowState]
    public var cursorPredictions: [CursorPrediction]
    public var predictionEpoch: Int
    public var confirmedEpoch: Int
    public var predictedCursorRow: Int
    public var predictedCursorCol: Int
    public var cols: Int
    public var rows: Int
}

public struct PredictionDebugMetrics: Equatable {
    public var sendIntervalMillis: Int64
    public var echoAck: Int64
    public var glitchTrigger: Int
    public var srttTrigger: Bool
    public var activePredictionCount: Int
}
