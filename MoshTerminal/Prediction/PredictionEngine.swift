import Foundation

final class PredictionEngine {
    private let parser = UTF8ByteParser()
    private var overlayRows: [OverlayRowState] = []
    private var cursorPredictions: [CursorPrediction] = []

    private var predictionEpoch = 0
    private var confirmedEpoch = 0
    private var lastUserByte: UInt8?

    private var cols = 0
    private var rows = 0
    private var predictedCursorRow = 0
    private var predictedCursorCol = 0

    private var localFrameSent: Int64 = 0
    private var localFrameAcked: Int64 = 0
    private var echoAck: Int64 = 0
    private var srttMillis: Int64 = 0

    func reset() {
        parser.reset()
        cursorPredictions.removeAll()
        overlayRows = makeEmptyRows()
        predictionEpoch = 0
        confirmedEpoch = 0
    }

    func updateNetworkSnapshot(_ snapshot: PredictionNetworkSnapshot) {
    }

    func newUserBytes(_ bytes: Data, displayGrid: DisplayGrid, nowMillis: Int64) {
        ensureGridSize(displayGrid)
        let actions = parser.feed(bytes)
        if let lastByte = bytes.last {
            lastUserByte = lastByte
        }

        if let lastCursor = cursorPredictions.last {
            predictedCursorRow = lastCursor.row
            predictedCursorCol = lastCursor.col
        } else {
            predictedCursorRow = displayGrid.cursorRow
            predictedCursorCol = displayGrid.cursorCol
        }

        for action in actions {
            switch action {
            case .print(let char, let width):
                guard width == 1 else {
                    becomeTentative()
                    continue
                }
                applyPrintable(char: char, width: width, displayGrid: displayGrid, nowMillis: nowMillis)

            case .backspace:
                applyBackspace(nowMillis: nowMillis)

            case .carriageReturn:
                applyCarriageReturn(nowMillis: nowMillis)

            case .arrowLeft:
                applyArrowLeft(nowMillis: nowMillis)

            case .arrowRight:
                applyArrowRight(nowMillis: nowMillis)

            case .unknown:
                becomeTentative()
            }
        }
    }

    func cull(confirmedGrid: DisplayGrid, nowMillis: Int64) {
    }

    func currentRenderModel(confirmedGrid: DisplayGrid, nowMillis: Int64) -> PredictionRenderModel {
        return PredictionRenderModel()
    }

    var debugState: PredictionDebugState {
        PredictionDebugState(
            overlayRows: overlayRows,
            cursorPredictions: cursorPredictions,
            predictionEpoch: predictionEpoch,
            confirmedEpoch: confirmedEpoch,
            predictedCursorRow: predictedCursorRow,
            predictedCursorCol: predictedCursorCol,
            cols: cols,
            rows: rows
        )
    }

    private func applyPrintable(char: Character, width: Int, displayGrid: DisplayGrid, nowMillis: Int64) {
        normalizeCursorForPrint()

        if displayGrid.isInsertMode {
            shiftRowRight(rowIndex: predictedCursorRow, startCol: predictedCursorCol)
        }

        let replacement = DisplayCell(char: char, width: width)
        let original = [displayGrid.cell(atRow: predictedCursorRow, col: predictedCursorCol)]
        let cell = OverlayCellState(
            active: true,
            col: predictedCursorCol,
            replacement: replacement,
            unknown: false,
            originalContents: original,
            expirationFrame: localFrameSent + 1,
            predictionTime: nowMillis,
            tentativeUntilEpoch: predictionEpoch
        )
        upsertCell(row: predictedCursorRow, cell: cell)

        predictedCursorCol += width
        if predictedCursorCol >= cols {
            predictedCursorCol = 0
            predictedCursorRow += 1
            becomeTentative()
            if predictedCursorRow >= rows {
                scrollOverlayUp()
                predictedCursorRow = max(rows - 1, 0)
            }
        }

        appendCursorPrediction(nowMillis: nowMillis)
    }

    private func applyBackspace(nowMillis: Int64) {
        if predictedCursorCol > 0 {
            predictedCursorCol -= 1
        }

        if predictedCursorRow >= 0 && predictedCursorRow < overlayRows.count {
            overlayRows[predictedCursorRow].unknownRow = true
        }

        let cell = OverlayCellState(
            active: true,
            col: predictedCursorCol,
            replacement: nil,
            unknown: true,
            originalContents: [],
            expirationFrame: localFrameSent + 1,
            predictionTime: nowMillis,
            tentativeUntilEpoch: predictionEpoch
        )
        upsertCell(row: predictedCursorRow, cell: cell)
        appendCursorPrediction(nowMillis: nowMillis)
    }

    private func applyCarriageReturn(nowMillis: Int64) {
        predictedCursorCol = 0
        predictedCursorRow += 1
        if predictedCursorRow >= rows {
            scrollOverlayUp()
            predictedCursorRow = max(rows - 1, 0)
        }
        becomeTentative()
        appendCursorPrediction(nowMillis: nowMillis)
    }

    private func applyArrowLeft(nowMillis: Int64) {
        if predictedCursorCol > 0 {
            predictedCursorCol -= 1
        }
        appendCursorPrediction(nowMillis: nowMillis)
    }

    private func applyArrowRight(nowMillis: Int64) {
        if predictedCursorCol < cols - 1 {
            predictedCursorCol += 1
        }
        appendCursorPrediction(nowMillis: nowMillis)
    }

    private func appendCursorPrediction(nowMillis: Int64) {
        let prediction = CursorPrediction(
            row: predictedCursorRow,
            col: predictedCursorCol,
            expirationFrame: localFrameSent + 1,
            predictionTime: nowMillis,
            tentativeUntilEpoch: predictionEpoch
        )
        cursorPredictions.append(prediction)
    }

    private func normalizeCursorForPrint() {
        if predictedCursorCol >= cols {
            predictedCursorCol = 0
            predictedCursorRow += 1
            becomeTentative()
        }
        if predictedCursorRow >= rows {
            scrollOverlayUp()
            predictedCursorRow = max(rows - 1, 0)
        }
    }

    private func shiftRowRight(rowIndex: Int, startCol: Int) {
        guard rowIndex >= 0, rowIndex < overlayRows.count else { return }
        var shifted: [OverlayCellState] = []
        for var cell in overlayRows[rowIndex].cells {
            if cell.col >= startCol {
                cell.col += 1
            }
            if cell.col < cols {
                shifted.append(cell)
            }
        }
        overlayRows[rowIndex].cells = shifted
    }

    private func upsertCell(row: Int, cell: OverlayCellState) {
        guard row >= 0, row < overlayRows.count else { return }
        var rowState = overlayRows[row]
        if let index = rowState.cells.firstIndex(where: { $0.col == cell.col }) {
            rowState.cells[index] = cell
        } else {
            rowState.cells.append(cell)
        }
        overlayRows[row] = rowState
    }

    private func scrollOverlayUp() {
        guard rows > 0 else { return }
        if overlayRows.isEmpty {
            overlayRows = makeEmptyRows()
            return
        }
        overlayRows.removeFirst()
        overlayRows.append(OverlayRowState(unknownRow: false, cells: []))
    }

    private func ensureGridSize(_ displayGrid: DisplayGrid) {
        if cols != displayGrid.cols || rows != displayGrid.rows {
            cols = displayGrid.cols
            rows = displayGrid.rows
            overlayRows = makeEmptyRows()
        }
    }

    private func makeEmptyRows() -> [OverlayRowState] {
        guard rows > 0 else { return [] }
        return (0..<rows).map { _ in OverlayRowState(unknownRow: false, cells: []) }
    }

    private func becomeTentative() {
        predictionEpoch += 1
    }
}
