import CoreText
import SwiftTerm
import UIKit

/// Prevents SwiftTerm from resizing to a zero/super-tiny grid during view removal.
/// This avoids buffer reflow artifacts like stray characters when navigating away and back.
final class StableTerminalView: TerminalUIKitView {
    override var bounds: CGRect {
        get { super.bounds }
        set {
            guard !shouldIgnore(size: newValue.size) else { return }
            super.bounds = newValue
        }
    }

    override var frame: CGRect {
        get { super.frame }
        set {
            guard !shouldIgnore(size: newValue.size) else { return }
            super.frame = newValue
        }
    }

    private func shouldIgnore(size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return true }
        let metrics = cellMetrics
        let cols = Int(size.width / metrics.cellWidth)
        let rows = Int(size.height / metrics.cellHeight)
        return cols < 2 || rows < 2
    }

    private var cellMetrics: (cellWidth: CGFloat, cellHeight: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let cellWidth = "W".size(withAttributes: attributes).width

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let cellHeight = ceil(ascent + descent + leading)

        return (max(1, cellWidth), max(1, min(cellHeight, 8192)))
    }
}
