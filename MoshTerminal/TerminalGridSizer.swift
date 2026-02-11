import CoreText
import UIKit

struct TerminalCellMetrics: Equatable {
    let cellWidth: CGFloat
    let cellHeight: CGFloat
}

enum TerminalGridSizer {
    static func metrics(for font: UIFont) -> TerminalCellMetrics {
        // Match SwiftTerm's grid metrics:
        // - width from the monospaced "W" advance
        // - height from CTFont ascent/descent/leading
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let cellWidth = "W".size(withAttributes: attributes).width

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let cellHeight = ceil(ascent + descent + leading)

        return TerminalCellMetrics(
            cellWidth: max(1, cellWidth),
            cellHeight: max(1, min(cellHeight, 8192))
        )
    }

    static func gridSize(availableSize: CGSize, font: UIFont) -> TerminalSize {
        let metrics = metrics(for: font)
        let cols = max(2, Int(floor(availableSize.width / metrics.cellWidth)))
        let rows = max(2, Int(floor(availableSize.height / metrics.cellHeight)))
        return TerminalSize(cols: cols, rows: rows)
    }
}

