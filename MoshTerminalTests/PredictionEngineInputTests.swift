import XCTest
@testable import MoshTerminal
@testable import Prediction

final class PredictionEngineInputTests: XCTestCase {
    func testTypingABCGeneratesOverlayCellsAndCursorMoves() {
        let grid = FakeDisplayGrid(cols: 10, rows: 3, cursorRow: 0, cursorCol: 0)
        let engine = PredictionEngine()

        engine.newUserBytes(Data("abc".utf8), displayGrid: grid, nowMillis: 1000)

        let state = engine.debugState
        XCTAssertEqual(state.cursorPredictions.last?.row, 0)
        XCTAssertEqual(state.cursorPredictions.last?.col, 3)

        let rowCells = state.overlayRows[0].cells
        XCTAssertEqual(rowCells.count, 3)
        XCTAssertTrue(rowCells.contains(where: { $0.col == 0 && $0.replacement?.char == "a" }))
        XCTAssertTrue(rowCells.contains(where: { $0.col == 1 && $0.replacement?.char == "b" }))
        XCTAssertTrue(rowCells.contains(where: { $0.col == 2 && $0.replacement?.char == "c" }))
    }

    func testBackspaceMarksUnknownCellAndMovesCursorLeft() {
        let grid = FakeDisplayGrid(cols: 10, rows: 3, cursorRow: 0, cursorCol: 3)
        let engine = PredictionEngine()

        engine.newUserBytes(Data([0x7F]), displayGrid: grid, nowMillis: 2000)

        let state = engine.debugState
        XCTAssertEqual(state.cursorPredictions.last?.row, 0)
        XCTAssertEqual(state.cursorPredictions.last?.col, 2)
        XCTAssertFalse(state.overlayRows[0].unknownRow)

        let rowCells = state.overlayRows[0].cells
        XCTAssertEqual(rowCells.count, 1)
        XCTAssertEqual(rowCells.first?.col, 9)
        XCTAssertEqual(rowCells.first?.unknown, true)
    }

    func testInsertModeShiftsRightAndMarksLastColumnUnknown() {
        let grid = FakeDisplayGrid(cols: 5, rows: 2, cursorRow: 0, cursorCol: 2, isInsertMode: true)
        let engine = PredictionEngine()

        engine.newUserBytes(Data("x".utf8), displayGrid: grid, nowMillis: 2500)

        let rowCells = engine.debugState.overlayRows[0].cells
        XCTAssertTrue(rowCells.contains(where: { $0.col == 2 && $0.replacement?.char == "x" }))
        XCTAssertTrue(rowCells.contains(where: { $0.col == 4 && $0.unknown }))
    }

    func testArrowLeftRightUpdatesCursorPrediction() {
        let grid = FakeDisplayGrid(cols: 10, rows: 3, cursorRow: 1, cursorCol: 5)
        let engine = PredictionEngine()

        engine.newUserBytes(Data([0x1B, 0x5B, 0x44]), displayGrid: grid, nowMillis: 3000)
        XCTAssertEqual(engine.debugState.cursorPredictions.last?.col, 4)

        engine.newUserBytes(Data([0x1B, 0x5B, 0x43]), displayGrid: grid, nowMillis: 3100)
        XCTAssertEqual(engine.debugState.cursorPredictions.last?.col, 5)
    }

    func testCarriageReturnMovesCursorToNextLineAndBecomesTentative() {
        let grid = FakeDisplayGrid(cols: 10, rows: 3, cursorRow: 0, cursorCol: 4)
        let engine = PredictionEngine()

        engine.newUserBytes(Data([0x0D]), displayGrid: grid, nowMillis: 4000)

        let state = engine.debugState
        XCTAssertEqual(state.cursorPredictions.last?.row, 1)
        XCTAssertEqual(state.cursorPredictions.last?.col, 0)
        XCTAssertEqual(state.predictionEpoch, 1)
    }

    func testInsertModeShiftsExistingPredictionsRight() {
        let grid = FakeDisplayGrid(cols: 5, rows: 1, cursorRow: 0, cursorCol: 0)
        let engine = PredictionEngine()

        engine.newUserBytes(Data("abc".utf8), displayGrid: grid, nowMillis: 1000)
        engine.newUserBytes(Data([0x1B, 0x5B, 0x44]), displayGrid: grid, nowMillis: 1010)
        engine.newUserBytes(Data([0x1B, 0x5B, 0x44]), displayGrid: grid, nowMillis: 1020)

        let insertGrid = FakeDisplayGrid(cols: 5, rows: 1, cursorRow: 0, cursorCol: 1, isInsertMode: true)
        engine.newUserBytes(Data("x".utf8), displayGrid: insertGrid, nowMillis: 1030)

        let rowCells = engine.debugState.overlayRows[0].cells
        XCTAssertEqual(replacementChar(in: rowCells, col: 0), "a")
        XCTAssertEqual(replacementChar(in: rowCells, col: 1), "x")
        XCTAssertEqual(replacementChar(in: rowCells, col: 2), "b")
        XCTAssertEqual(replacementChar(in: rowCells, col: 3), "c")
        XCTAssertTrue(rowCells.contains(where: { $0.col == 4 && $0.unknown }))
    }

    func testBackspaceShiftsExistingPredictionsLeft() {
        let grid = FakeDisplayGrid(cols: 5, rows: 1, cursorRow: 0, cursorCol: 0)
        let engine = PredictionEngine()

        engine.newUserBytes(Data("abcd".utf8), displayGrid: grid, nowMillis: 2000)
        engine.newUserBytes(Data([0x1B, 0x5B, 0x44]), displayGrid: grid, nowMillis: 2010)
        engine.newUserBytes(Data([0x1B, 0x5B, 0x44]), displayGrid: grid, nowMillis: 2020)
        engine.newUserBytes(Data([0x7F]), displayGrid: grid, nowMillis: 2030)

        let rowCells = engine.debugState.overlayRows[0].cells
        XCTAssertEqual(replacementChar(in: rowCells, col: 0), "a")
        XCTAssertEqual(replacementChar(in: rowCells, col: 1), "c")
        XCTAssertEqual(replacementChar(in: rowCells, col: 2), "d")
        XCTAssertNil(replacementChar(in: rowCells, col: 3))
        XCTAssertTrue(rowCells.contains(where: { $0.col == 4 && $0.unknown }))
    }
}

private struct FakeDisplayGrid: DisplayGrid {
    let cols: Int
    let rows: Int
    let cursorRow: Int
    let cursorCol: Int
    let isInsertMode: Bool
    private let cells: [[DisplayCell]]

    init(cols: Int, rows: Int, cursorRow: Int, cursorCol: Int, isInsertMode: Bool = false, fill: DisplayCell = .blank) {
        self.cols = cols
        self.rows = rows
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.isInsertMode = isInsertMode
        self.cells = (0..<rows).map { _ in (0..<cols).map { _ in fill } }
    }

    func cell(atRow row: Int, col: Int) -> DisplayCell {
        guard row >= 0, row < rows, col >= 0, col < cols else {
            return .blank
        }
        return cells[row][col]
    }
}

private func replacementChar(in cells: [OverlayCellState], col: Int) -> Character? {
    cells.first(where: { $0.col == col })?.replacement?.char
}
