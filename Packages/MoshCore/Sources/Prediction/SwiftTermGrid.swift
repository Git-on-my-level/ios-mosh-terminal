import Foundation
import SwiftTerm

final class SwiftTermConfirmedGrid: DisplayGrid {
    private let terminal: Terminal

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    var cols: Int { terminal.cols }
    var rows: Int { terminal.rows }

    var cursorRow: Int {
        terminal.getCursorLocation().y
    }

    var cursorCol: Int {
        terminal.getCursorLocation().x
    }

    func cell(atRow row: Int, col: Int) -> DisplayCell {
        guard let charData = terminal.getCharData(col: col, row: row) else {
            return .blank
        }
        let char = terminal.getCharacter(for: charData)
        if char == "\u{0}" {
            return .blank
        }
        let width = max(1, Int(charData.width))
        return DisplayCell(char: char, width: width)
    }
}

struct PredictedDisplayGrid: DisplayGrid {
    private let confirmedGrid: DisplayGrid
    private let renderModel: PredictionRenderModel

    init(confirmedGrid: DisplayGrid, renderModel: PredictionRenderModel) {
        self.confirmedGrid = confirmedGrid
        self.renderModel = renderModel
    }

    var cols: Int { confirmedGrid.cols }
    var rows: Int { confirmedGrid.rows }
    var isInsertMode: Bool { confirmedGrid.isInsertMode }

    var cursorRow: Int {
        renderModel.cursorPredictions.last?.row ?? confirmedGrid.cursorRow
    }

    var cursorCol: Int {
        renderModel.cursorPredictions.last?.col ?? confirmedGrid.cursorCol
    }

    func cell(atRow row: Int, col: Int) -> DisplayCell {
        guard renderModel.showPredictions else {
            return confirmedGrid.cell(atRow: row, col: col)
        }
        guard row >= 0, row < renderModel.overlayRows.count else {
            return confirmedGrid.cell(atRow: row, col: col)
        }
        let rowState = renderModel.overlayRows[row]
        if let overlayCell = rowState.cells.first(where: { $0.col == col }),
           let replacement = overlayCell.replacement {
            return replacement
        }
        return confirmedGrid.cell(atRow: row, col: col)
    }
}
