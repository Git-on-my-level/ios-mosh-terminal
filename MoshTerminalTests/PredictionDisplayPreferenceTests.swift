import XCTest
@testable import MoshTerminal

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
        let pos = CellPosition(row: row, col: col)
        return overrides[pos] ?? fill
    }
}

private func visibleCells(in model: PredictionRenderModel) -> [OverlayCellState] {
    model.overlayRows.flatMap { $0.cells }
}

final class PredictionDisplayPreferenceTests: XCTestCase {
    func testOffPreferenceHidesPredictionsEvenWhenAvailable() {
        let engine = PredictionEngine()
        engine.displayPreference = .off
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data("h".utf8), displayGrid: grid, nowMillis: 1000)
        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 10)
        )

        let confirmed = FakeDisplayGrid(
            cols: 5,
            rows: 3,
            cursorRow: 0,
            cursorCol: 1,
            overrides: [CellPosition(row: 0, col: 0): DisplayCell(char: "h", width: 1)]
        )
        engine.cull(confirmedGrid: confirmed, nowMillis: 1100, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 1100)
        XCTAssertFalse(render.showPredictions, "Off preference should hide predictions")
        XCTAssertTrue(visibleCells(in: render).isEmpty, "Off preference should show no visible cells")
    }

    func testAlwaysPreferenceShowsPredictionsWhenAvailable() {
        let engine = PredictionEngine()
        engine.displayPreference = .always
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data("h".utf8), displayGrid: grid, nowMillis: 1000)

        let confirmed = FakeDisplayGrid(
            cols: 5,
            rows: 3,
            cursorRow: 0,
            cursorCol: 1,
            overrides: [CellPosition(row: 0, col: 0): DisplayCell(char: "h", width: 1)]
        )
        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 10)
        )

        let render = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 1100)
        XCTAssertTrue(render.showPredictions, "Always preference should show predictions")
        XCTAssertFalse(visibleCells(in: render).isEmpty, "Always preference should show visible cells")
    }

    func testAdaptivePreferenceHidesPredictionsWhenLatencyLow() {
        let engine = PredictionEngine()
        engine.displayPreference = .adaptive
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 10)
        )
        engine.cull(confirmedGrid: grid, nowMillis: 1000, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1000)
        XCTAssertFalse(render.showPredictions, "Adaptive should hide predictions when latency is low")
    }

    func testAdaptivePreferenceShowsPredictionsWhenSrttTriggerTrue() {
        let engine = PredictionEngine()
        engine.displayPreference = .adaptive
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data("h".utf8), displayGrid: grid, nowMillis: 1000)
        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 70)
        )

        let confirmed = FakeDisplayGrid(
            cols: 5,
            rows: 3,
            cursorRow: 0,
            cursorCol: 1,
            overrides: [CellPosition(row: 0, col: 0): DisplayCell(char: "h", width: 1)]
        )
        engine.cull(confirmedGrid: confirmed, nowMillis: 1100, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 1100)
        XCTAssertTrue(render.showPredictions, "Adaptive should show predictions when SRTT trigger is true")
    }

    func testAdaptivePreferenceShowsPredictionsWhenGlitchTriggerActive() {
        let engine = PredictionEngine()
        engine.displayPreference = .adaptive
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data("h".utf8), displayGrid: grid, nowMillis: 1000)
        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 0, srttMillis: 10)
        )

        let confirmed = FakeDisplayGrid(
            cols: 5,
            rows: 3,
            cursorRow: 0,
            cursorCol: 0
        )

        engine.cull(confirmedGrid: confirmed, nowMillis: 1100, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 1100)
        XCTAssertFalse(render.showPredictions, "Adaptive should hide predictions with no glitch trigger")

        engine.cull(confirmedGrid: confirmed, nowMillis: 5000, didReceiveOutput: false)

        let renderWithGlitch = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 5000)
        XCTAssertTrue(renderWithGlitch.showPredictions, "Adaptive should show predictions when glitch trigger is active")
    }

    func testExperimentalPreferenceShowsPredictionsWithUnknownState() {
        let engine = PredictionEngine()
        engine.displayPreference = .experimental
        let grid = FakeDisplayGrid(cols: 5, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.newUserBytes(Data([0x08]), displayGrid: grid, nowMillis: 1000)
        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 0, lastAckedStateNum: 0, echoAck: 1, srttMillis: 10)
        )
        engine.cull(confirmedGrid: grid, nowMillis: 1100, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1100)
        XCTAssertTrue(render.showPredictions, "Experimental preference should show predictions")
    }
}
