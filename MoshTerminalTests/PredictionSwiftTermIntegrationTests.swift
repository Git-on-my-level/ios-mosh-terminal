import XCTest
@testable import MoshTerminal
@testable import Prediction

private struct CellPosition: Hashable {
    let row: Int
    let col: Int
}

final class PredictionSwiftTermIntegrationTests: XCTestCase {

    func testEchoShellShowsPredictionsAfterFirstCorrectEcho() {
        let engine = PredictionEngine()
        engine.displayPreference = .always

        let grid = SwiftTermConfirmedGrid(cols: 10, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 1, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("\r".utf8), displayGrid: grid, nowMillis: 1000)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("abc".utf8), displayGrid: grid, nowMillis: 1010)

        engine.cull(confirmedGrid: grid, nowMillis: 1010, didReceiveOutput: false)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("\r".utf8), displayGrid: grid, nowMillis: 1000)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("abc".utf8), displayGrid: grid, nowMillis: 1010)

        engine.cull(confirmedGrid: grid, nowMillis: 1010, didReceiveOutput: false)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("\r".utf8), displayGrid: grid, nowMillis: 1000)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("abc".utf8), displayGrid: grid, nowMillis: 1010)

        engine.cull(confirmedGrid: grid, nowMillis: 1010, didReceiveOutput: false)

        let confirmed = SwiftTermConfirmedGrid(
            cols: 10,
            rows: 3,
            cursorRow: 1,
            cursorCol: 1,
            overrides: [CellPosition(row: 1, col: 0): DisplayCell(char: "a", width: 1)]
        )

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 1, srttMillis: 40))
        engine.cull(confirmedGrid: confirmed, nowMillis: 1100, didReceiveOutput: false)

        let render = engine.currentRenderModel(confirmedGrid: confirmed, nowMillis: 1100)
        let cells = visibleCells(in: render)

        let visibleBs = cells.filter { $0.replacement?.char == "b" || $0.replacement?.char == "c" }
        XCTAssertEqual(visibleBs.count, 2)
        XCTAssertTrue(visibleBs.contains(where: { $0.replacement?.char == "b" }))
        XCTAssertTrue(visibleBs.contains(where: { $0.replacement?.char == "c" }))
    }

    func testPasswordPromptNeverShowsPredictions() {
        let engine = PredictionEngine()
        engine.displayPreference = .always

        let grid = SwiftTermConfirmedGrid(cols: 10, rows: 3, cursorRow: 0, cursorCol: 0)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 1, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("\r".utf8), displayGrid: grid, nowMillis: 1000)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data("p@ssw0rd".utf8), displayGrid: grid, nowMillis: 1010)

        engine.cull(confirmedGrid: grid, nowMillis: 1010, didReceiveOutput: false)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.cull(confirmedGrid: grid, nowMillis: 1010, didReceiveOutput: false)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 1, srttMillis: 40))
        engine.cull(confirmedGrid: grid, nowMillis: 1010, didReceiveOutput: false)

        var render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1010)
        XCTAssertTrue(visibleCells(in: render).isEmpty)

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 2, lastAckedStateNum: 0, echoAck: 2, srttMillis: 40))
        engine.cull(confirmedGrid: grid, nowMillis: 1010, didReceiveOutput: false)

        render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1010)
        XCTAssertTrue(visibleCells(in: render).isEmpty)
    }

    func testBackspaceOnLineWithExistingText() {
        let engine = PredictionEngine()
        engine.displayPreference = .always

        let grid = SwiftTermConfirmedGrid(
            cols: 10,
            rows: 3,
            cursorRow: 0,
            cursorCol: 5,
            overrides: [CellPosition(row: 0, col: 0): DisplayCell(char: "h", width: 1),
                         CellPosition(row: 0, col: 1): DisplayCell(char: "e", width: 1),
                         CellPosition(row: 0, col: 2): DisplayCell(char: "l", width: 1),
                         CellPosition(row: 0, col: 3): DisplayCell(char: "l", width: 1),
                         CellPosition(row: 0, col: 4): DisplayCell(char: "o", width: 1)]
        )

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 1, lastAckedStateNum: 0, echoAck: 0, srttMillis: 40))
        engine.newUserBytes(Data([0x7F]), displayGrid: grid, nowMillis: 1000)

        engine.cull(confirmedGrid: grid, nowMillis: 1000, didReceiveOutput: false)

        var render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1000)
        XCTAssertTrue(render.cursorPredictions.contains(where: { $0.row == 0 && $0.col == 4 }))

        engine.updateNetworkSnapshot(
            PredictionNetworkSnapshot(lastSentStateNum: 1, lastAckedStateNum: 0, echoAck: 1, srttMillis: 40))
        engine.cull(confirmedGrid: grid, nowMillis: 1100, didReceiveOutput: false)

        render = engine.currentRenderModel(confirmedGrid: grid, nowMillis: 1100)
        let cells = visibleCells(in: render)
        XCTAssertEqual(cells.count, 1)
        XCTAssertFalse(cells.first?.unknown == true)
        XCTAssertEqual(cells.first?.replacement, DisplayCell.blank)
        XCTAssertEqual(cells.first?.col, 4)
    }
}

private func visibleCells(in model: PredictionRenderModel) -> [OverlayCellState] {
    model.overlayRows.flatMap { $0.cells }
}

private final class SwiftTermConfirmedGrid: DisplayGrid {
    let cols: Int
    let rows: Int
    private var buffer: [[DisplayCell]]
    private var cursor: (row: Int, col: Int)

    var cursorRow: Int { cursor.row }
    var cursorCol: Int { cursor.col }
    var isInsertMode: Bool { false }

    private func setupBuffer(cols: Int, rows: Int, overrides: [CellPosition: DisplayCell]) {
        self.buffer = (0..<rows).map { row in
            (0..<cols).map { col in
                overrides[CellPosition(row: row, col: col)] ?? DisplayCell.blank
            }
        }
    }

    init(cols: Int, rows: Int, cursorRow: Int, cursorCol: Int) {
        self.cols = cols
        self.rows = rows
        self.cursor = (row: cursorRow, col: cursorCol)
        self.buffer = (0..<rows).map { _ in (0..<cols).map { _ in DisplayCell.blank } }
    }

    convenience init(cols: Int, rows: Int, cursorRow: Int, cursorCol: Int, overrides: [CellPosition: DisplayCell] = [:]) {
        self.init(cols: cols, rows: rows, cursorRow: cursorRow, cursorCol: cursorCol)
        setupBuffer(cols: cols, rows: rows, overrides: overrides)
    }

    func cell(atRow row: Int, col: Int) -> DisplayCell {
        guard row >= 0, row < rows, col >= 0, col < cols else {
            return .blank
        }
        return buffer[row][col]
    }
}
