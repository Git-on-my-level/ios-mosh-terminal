import XCTest
@testable import MoshTerminal

final class PredictionEngineCullTests: XCTestCase {
    func testEpochGatingHidesPostCarriageReturnCharacterUntilConfirmed() {
        let engine = PredictionEngine()
        engine.displayPreference = .always
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data([0x0D]), displayGrid: grid, nowMillis: 1000)
        engine.newUserBytes(Data("a".utf8), displayGrid: grid, nowMillis: 1010)

        let preConfirm = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1015)
        XCTAssertTrue(visibleCells(in: preConfirm).isEmpty)

        let confirmed = FakeDisplayGrid(
            cols: 5,
            rows: 3,
            cursorRow: 1,
            cursorCol: 1,
            overrides: [CellPosition(row: 1, col: 0): DisplayCell(char: "a", width: 1)]
        )
        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 10)
        )
        engine.cull(confirmedGrid: confirmed, nowMillis: 1100, didReceiveOutput: false)

        let postConfirm = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 1100)
        XCTAssertTrue(visibleCells(in: postConfirm).isEmpty)
    }

    func testNoEchoPasswordNeverShowsPredictionsEvenAfterEchoAck() {
        let engine = PredictionEngine()
        engine.displayPreference = .always
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data([0x0D]), displayGrid: grid, nowMillis: 1000)
        engine.newUserBytes(Data("p".utf8), displayGrid: grid, nowMillis: 1010)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 10)
        )
        engine.cull(confirmedGrid: grid, nowMillis: 1200, didReceiveOutput: false)

        var render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1200)
        XCTAssertTrue(visibleCells(in: render).isEmpty)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 2, srttMillis: 10)
        )
        engine.cull(confirmedGrid: grid, nowMillis: 1300, didReceiveOutput: false)

        render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1300)
        XCTAssertTrue(visibleCells(in: render).isEmpty)
    }

    func testIncorrectPredictionAfterDisplayedTriggersReset() {
        let engine = PredictionEngine()
        engine.displayPreference = .always
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data("a".utf8), displayGrid: grid, nowMillis: 1000)
        let preCull = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1000)
        XCTAssertFalse(visibleCells(in: preCull).isEmpty)

        let confirmed = FakeDisplayGrid(
            cols: 5,
            rows: 3,
            cursorRow: 0,
            cursorCol: 0,
            overrides: [CellPosition(row: 0, col: 0): DisplayCell(char: "b", width: 1)]
        )
        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 10)
        )
        engine.cull(confirmedGrid: confirmed, nowMillis: 1100, didReceiveOutput: false)

        let state = engine.debugState
        XCTAssertTrue(state.cursorPredictions.isEmpty)
        XCTAssertTrue(state.overlayRows.flatMap { $0.cells }.allSatisfy { !$0.active })
    }

    func testLowSrttDoesNotShowPredictions() {
        let engine = PredictionEngine()
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 0, srttMillis: 10)
        )
        engine.newUserBytes(Data("a".utf8), displayGrid: grid, nowMillis: 1000)
        engine.cull(confirmedGrid: grid, nowMillis: 1000, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1000)
        XCTAssertFalse(render.showPredictions)
        XCTAssertTrue(visibleCells(in: render).isEmpty)
    }

    func testHighSrttShowsPredictions() {
        let engine = PredictionEngine()
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40)
        )
        engine.newUserBytes(Data("a".utf8), displayGrid: grid, nowMillis: 1000)
        engine.cull(confirmedGrid: grid, nowMillis: 1000, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1000)
        XCTAssertTrue(render.showPredictions)
        XCTAssertFalse(visibleCells(in: render).isEmpty)
    }

    func testDefaultSrttShowsPredictionsInAdaptiveMode() {
        let engine = PredictionEngine()
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data("a".utf8), displayGrid: grid, nowMillis: 1000)
        engine.cull(confirmedGrid: grid, nowMillis: 1000, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1000)
        XCTAssertTrue(render.showPredictions)
        XCTAssertFalse(visibleCells(in: render).isEmpty)
    }

    func testEarlyConfirmAdvancesConfirmedEpoch() {
        let engine = PredictionEngine()
        engine.displayPreference = .always
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data([0x0D]), displayGrid: grid, nowMillis: 1000)
        engine.newUserBytes(Data("ab".utf8), displayGrid: grid, nowMillis: 1010)

        let confirmed = FakeDisplayGrid(
            cols: 5,
            rows: 3,
            cursorRow: 1,
            cursorCol: 1,
            overrides: [CellPosition(row: 1, col: 0): DisplayCell(char: "a", width: 1)]
        )

        engine.cull(confirmedGrid: confirmed, nowMillis: 1020, didReceiveOutput: false)

        XCTAssertEqual(engine.debugState.confirmedEpoch, 1)
        let render = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 1020)
        XCTAssertTrue(visibleCells(in: render).contains(where: { $0.replacement?.char == "b" }))
    }

    func testGlitchTriggerShowsPredictionsAfterLongPending() {
        let engine = PredictionEngine()
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 0, srttMillis: 10)
        )
        engine.newUserBytes(Data("a".utf8), displayGrid: grid, nowMillis: 1000)
        engine.cull(confirmedGrid: grid, nowMillis: 1300, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1300)
        XCTAssertTrue(render.showPredictions)
        XCTAssertFalse(visibleCells(in: render).isEmpty)
    }
}

private struct CellPosition: Hashable {
    let row: Int
    let col: Int
}

private struct FakeDisplayGrid: DisplayGrid {
    let cols: Int
    let rows: Int
    let cursorRow: Int
    let cursorCol: Int
    let isInsertMode: Bool
    private let fill: DisplayCell
    private let overrides: [CellPosition: DisplayCell]

    init(
        cols: Int,
        rows: Int,
        cursorRow: Int,
        cursorCol: Int,
        isInsertMode: Bool = false,
        fill: DisplayCell = .blank,
        overrides: [CellPosition: DisplayCell] = [:]
    ) {
        self.cols = cols
        self.rows = rows
        self.cursorRow = cursorRow
        self.cursorCol = cursorCol
        self.isInsertMode = isInsertMode
        self.fill = fill
        self.overrides = overrides
    }

    func cell(atRow row: Int, col: Int) -> DisplayCell {
        guard row >= 0, row < rows, col >= 0, col < cols else {
            return .blank
        }
        return overrides[CellPosition(row: row, col: col)] ?? fill
    }
}

private func visibleCells(in model: PredictionRenderModel) -> [OverlayCellState] {
    model.overlayRows.flatMap { $0.cells }
}
