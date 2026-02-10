import XCTest
@testable import MoshTerminal

final class TerminalGridSizerTests: XCTestCase {
    func testGridSizeFloorsToWholeCellsAndMinimum2x2() {
        // Use a font with stable metrics; we don't assert exact numbers from CoreText,
        // only the flooring/minimum behavior.
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let metrics = TerminalGridSizer.metrics(for: font)

        // Make an available size that is just under 2 cells in each dimension.
        let underTwoCols = (metrics.cellWidth * 2) - 0.1
        let underTwoRows = (metrics.cellHeight * 2) - 0.1
        let size = CGSize(width: underTwoCols, height: underTwoRows)

        let grid = TerminalGridSizer.gridSize(availableSize: size, font: font)
        XCTAssertEqual(grid.cols, 2)
        XCTAssertEqual(grid.rows, 2)
    }

    func testAccessoryHeightReducesRows() {
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let metrics = TerminalGridSizer.metrics(for: font)

        let baseHeight = metrics.cellHeight * 10
        let baseSize = CGSize(width: metrics.cellWidth * 40, height: baseHeight)
        let baseGrid = TerminalGridSizer.gridSize(availableSize: baseSize, font: font)

        let reducedSize = CGSize(width: baseSize.width, height: baseSize.height - (metrics.cellHeight * 2))
        let reducedGrid = TerminalGridSizer.gridSize(availableSize: reducedSize, font: font)

        XCTAssertEqual(baseGrid.cols, reducedGrid.cols)
        XCTAssertTrue(reducedGrid.rows <= baseGrid.rows - 1)
    }
}

