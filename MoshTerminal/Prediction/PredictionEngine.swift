import Foundation

final class PredictionEngine {
    private enum Validity {
        case pending
        case correct
        case correctNoCredit
        case incorrectOrExpired
        case inactive
    }

    private enum Constants {
        static let srttTriggerLow: Int64 = 20
        static let srttTriggerHigh: Int64 = 30
        static let flagTriggerLow: Int64 = 50
        static let flagTriggerHigh: Int64 = 80
        static let glitchThreshold: Int64 = 250
        static let glitchRepairCount: Int = 10
        static let glitchRepairMinInterval: Int64 = 150
        static let glitchFlagThreshold: Int64 = 5000
    }

    private let parser = UTF8ByteParser()
    private var overlayRows: [OverlayRowState] = []
    private var cursorPredictions: [CursorPrediction] = []
    private var activeCellPositions: Set<CellPosition> = []
    private var activeRowIndices: Set<Int> = []

    private var predictionEpoch = 0
    private var confirmedEpoch = 0
    private var lastUserByte: UInt8?
    var displayPreference: PredictionDisplayPreference = .adaptive

    private var cols = 0
    private var rows = 0
    private var predictedCursorRow = 0
    private var predictedCursorCol = 0

    private var localFrameSent: Int64 = 0
    private var localFrameAcked: Int64 = 0
    private var echoAck: Int64 = 0
    private var srttMillis: Int64 = 0
    private var srttTrigger = false
    private var glitchTrigger = 0
    private var underlinePredictions = false
    private var lastQuickConfirmation: Int64 = 0

    func reset() {
        parser.reset()
        cursorPredictions.removeAll()
        activeCellPositions.removeAll()
        activeRowIndices.removeAll()
        overlayRows = makeEmptyRows()
        predictionEpoch = 0
        confirmedEpoch = 0
    }

    func updateNetworkSnapshot(_ snapshot: PredictionNetworkSnapshot) {
        localFrameSent = Int64(snapshot.lastSentStateNum)
        localFrameAcked = Int64(snapshot.lastAckedStateNum)
        echoAck = Int64(snapshot.echoAck)
        srttMillis = snapshot.srttMillis.map { Int64($0) } ?? 0
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
        if displayPreference == .off {
            return
        }

        if cols != confirmedGrid.cols || rows != confirmedGrid.rows {
            cols = confirmedGrid.cols
            rows = confirmedGrid.rows
            reset()
            overlayRows = makeEmptyRows()
            activeCellPositions.removeAll()
            activeRowIndices.removeAll()
            return
        }

        if srttMillis > Constants.srttTriggerHigh {
            srttTrigger = true
        } else if srttTrigger && srttMillis <= Constants.srttTriggerLow && !hasActivePredictions() {
            srttTrigger = false
        }

        if srttMillis > Constants.flagTriggerHigh {
            underlinePredictions = true
        } else if srttMillis <= Constants.flagTriggerLow {
            underlinePredictions = false
        }

        if glitchTrigger > Constants.glitchRepairCount {
            underlinePredictions = true
        }

        var earlyConfirmedRows: Set<Int> = []
        for rowIndex in activeRowIndices {
            guard rowIndex < overlayRows.count else { continue }
            for cellIndex in overlayRows[rowIndex].cells.indices {
                var cell = overlayRows[rowIndex].cells[cellIndex]
                if echoAck < cell.expirationFrame,
                   cell.active,
                   !cell.unknown,
                   let replacement = cell.replacement,
                   replacement != .blank {
                    let current = confirmedGrid.cell(atRow: rowIndex, col: cell.col)
                    if current == replacement,
                       !cell.originalContents.contains(where: { $0 == replacement }) {
                        earlyConfirmedRows.insert(rowIndex)
                        resetCell(&cell, row: rowIndex)
                        overlayRows[rowIndex].cells[cellIndex] = cell
                        continue
                    }
                }
                switch cellValidity(cell, row: rowIndex, confirmedGrid: confirmedGrid) {
                case .incorrectOrExpired:
                    if cell.tentativeUntilEpoch > confirmedEpoch {
                        if displayPreference == .experimental {
                            resetCell(&cell, row: rowIndex)
                        } else {
                            killEpoch(epoch: cell.tentativeUntilEpoch, confirmedGrid: confirmedGrid, nowMillis: nowMillis)
                            return
                        }
                    } else {
                        if displayPreference == .experimental {
                            resetCell(&cell, row: rowIndex)
                        } else {
                            reset()
                            return
                        }
                    }

                case .correct:
                    if cell.tentativeUntilEpoch > confirmedEpoch {
                        confirmedEpoch = cell.tentativeUntilEpoch
                    }

                    if nowMillis - cell.predictionTime < Constants.glitchThreshold,
                       glitchTrigger > 0,
                       nowMillis - Constants.glitchRepairMinInterval >= lastQuickConfirmation {
                        glitchTrigger -= 1
                        lastQuickConfirmation = nowMillis
                    }

                    resetCell(&cell, row: rowIndex)

                case .correctNoCredit:
                    resetCell(&cell, row: rowIndex)

                case .pending:
                    let age = nowMillis - cell.predictionTime
                    if age >= Constants.glitchFlagThreshold {
                        glitchTrigger = Constants.glitchRepairCount * 2
                    } else if age >= Constants.glitchThreshold, glitchTrigger < Constants.glitchRepairCount {
                        glitchTrigger = Constants.glitchRepairCount
                    }

                case .inactive:
                    break
                }
                overlayRows[rowIndex].cells[cellIndex] = cell
            }
        }
        
        if !earlyConfirmedRows.isEmpty {
            for rowIndex in earlyConfirmedRows {
                guard rowIndex < overlayRows.count else { continue }
                for cellIndex in overlayRows[rowIndex].cells.indices {
                    if overlayRows[rowIndex].cells[cellIndex].active {
                        overlayRows[rowIndex].cells[cellIndex].tentativeUntilEpoch = confirmedEpoch
                    }
                }
            }
        }

        if let lastCursor = cursorPredictions.last,
           cursorValidity(lastCursor, confirmedGrid: confirmedGrid) == .incorrectOrExpired {
            if displayPreference == .experimental {
                cursorPredictions.removeAll()
            } else {
                reset()
                return
            }
        }

        cursorPredictions = cursorPredictions.filter {
            cursorValidity($0, confirmedGrid: confirmedGrid) == .pending
        }
    }

    func currentRenderModel(confirmedGrid: DisplayGrid, nowMillis: Int64) -> PredictionRenderModel {
        let show = shouldShowPredictions()
        guard show else {
            return PredictionRenderModel()
        }

        let filteredRows = overlayRows.enumerated().map { index, row in
            let visibleCells = row.cells.filter { cell in
                cell.active && cell.tentativeUntilEpoch <= confirmedEpoch
            }
            let hasVisibleCells = !visibleCells.isEmpty
            let visibleUnknown = row.unknownRow && hasVisibleCells
            return OverlayRowState(unknownRow: visibleUnknown, cells: visibleCells)
        }

        let visibleCursors = cursorPredictions.filter { $0.tentativeUntilEpoch <= confirmedEpoch }

        return PredictionRenderModel(
            overlayRows: filteredRows,
            cursorPredictions: visibleCursors,
            showPredictions: show,
            underlinePredictions: underlinePredictions
        )
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
        let positionsToRemove = activeCellPositions.filter { pos in pos.row == rowIndex && pos.col >= startCol }
        for pos in positionsToRemove {
            activeCellPositions.remove(pos)
        }
        for var cell in overlayRows[rowIndex].cells {
            if cell.col >= startCol {
                cell.col += 1
            }
            if cell.col < cols {
                shifted.append(cell)
                if cell.active {
                    activeCellPositions.insert(CellPosition(row: rowIndex, col: cell.col))
                }
            }
        }
        overlayRows[rowIndex].cells = shifted
    }

    private func upsertCell(row: Int, cell: OverlayCellState) {
        guard row >= 0, row < overlayRows.count else { return }
        var rowState = overlayRows[row]
        if let index = rowState.cells.firstIndex(where: { $0.col == cell.col }) {
            let oldCell = rowState.cells[index]
            if !oldCell.active {
                activeCellPositions.remove(CellPosition(row: row, col: cell.col))
            }
            rowState.cells[index] = cell
        } else {
            rowState.cells.append(cell)
        }
        if cell.active {
            activeCellPositions.insert(CellPosition(row: row, col: cell.col))
            activeRowIndices.insert(row)
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
        if !activeRowIndices.isEmpty || !activeCellPositions.isEmpty || !cursorPredictions.isEmpty {
            var shiftedRowIndices: Set<Int> = []
            for row in activeRowIndices {
                if row > 0 {
                    shiftedRowIndices.insert(row - 1)
                }
            }
            activeRowIndices = shiftedRowIndices

            var shiftedPositions: Set<CellPosition> = []
            for pos in activeCellPositions {
                if pos.row > 0 {
                    shiftedPositions.insert(CellPosition(row: pos.row - 1, col: pos.col))
                }
            }
            activeCellPositions = shiftedPositions

            cursorPredictions = cursorPredictions.compactMap { prediction in
                guard prediction.row > 0 else {
                    return nil
                }
                return CursorPrediction(
                    row: prediction.row - 1,
                    col: prediction.col,
                    expirationFrame: prediction.expirationFrame,
                    predictionTime: prediction.predictionTime,
                    tentativeUntilEpoch: prediction.tentativeUntilEpoch
                )
            }
        }
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

    private func cellValidity(_ cell: OverlayCellState, row: Int, confirmedGrid: DisplayGrid) -> Validity {
        if !cell.active {
            return .inactive
        }
        if row >= confirmedGrid.rows || cell.col >= confirmedGrid.cols {
            return .incorrectOrExpired
        }
        if echoAck < cell.expirationFrame {
            guard !cell.unknown, let replacement = cell.replacement, replacement != .blank else {
                return .pending
            }
            return .pending
        }
        let current = confirmedGrid.cell(atRow: row, col: cell.col)
        if cell.unknown {
            return .correctNoCredit
        }
        guard let replacement = cell.replacement else {
            return .correctNoCredit
        }
        if replacement == .blank {
            return .correctNoCredit
        }
        if current == replacement {
            if cell.originalContents.contains(where: { $0 == replacement }) {
                return .correctNoCredit
            }
            return .correct
        }
        return .incorrectOrExpired
    }

    private func cursorValidity(_ prediction: CursorPrediction, confirmedGrid: DisplayGrid) -> Validity {
        if prediction.row >= confirmedGrid.rows || prediction.col >= confirmedGrid.cols {
            return .incorrectOrExpired
        }
        if echoAck >= prediction.expirationFrame {
            if confirmedGrid.cursorRow == prediction.row && confirmedGrid.cursorCol == prediction.col {
                return .correct
            }
            return .incorrectOrExpired
        }
        return .pending
    }

    private func resetCell(_ cell: inout OverlayCellState, row: Int) {
        if cell.active {
            activeCellPositions.remove(CellPosition(row: row, col: cell.col))
        }
        cell.active = false
        cell.replacement = nil
        cell.unknown = false
        cell.originalContents.removeAll()
        cell.expirationFrame = 0
        cell.predictionTime = 0
        if overlayRows.indices.contains(row) && overlayRows[row].cells.allSatisfy({ !$0.active }) {
            activeRowIndices.remove(row)
        }
    }

    private func killEpoch(epoch: Int, confirmedGrid: DisplayGrid, nowMillis: Int64) {
        cursorPredictions.removeAll { $0.tentativeUntilEpoch > epoch - 1 }

        predictedCursorRow = confirmedGrid.cursorRow
        predictedCursorCol = confirmedGrid.cursorCol
        let resetCursor = CursorPrediction(
            row: predictedCursorRow,
            col: predictedCursorCol,
            expirationFrame: localFrameSent + 1,
            predictionTime: nowMillis,
            tentativeUntilEpoch: predictionEpoch
        )
        cursorPredictions.append(resetCursor)

        for rowIndex in activeRowIndices {
            guard rowIndex < overlayRows.count else { continue }
            for cellIndex in overlayRows[rowIndex].cells.indices {
                if overlayRows[rowIndex].cells[cellIndex].tentativeUntilEpoch > epoch - 1 {
                    var cell = overlayRows[rowIndex].cells[cellIndex]
                    resetCell(&cell, row: rowIndex)
                    overlayRows[rowIndex].cells[cellIndex] = cell
                }
            }
        }

        becomeTentative()
    }

    private func hasActivePredictions() -> Bool {
        if !cursorPredictions.isEmpty {
            return true
        }
        return !activeCellPositions.isEmpty
    }

    private func shouldShowPredictions() -> Bool {
        switch displayPreference {
        case .off:
            return false
        case .always, .experimental:
            return true
        case .adaptive:
            return srttTrigger || glitchTrigger > 0
        }
    }

    private func becomeTentative() {
        predictionEpoch += 1
    }
}
