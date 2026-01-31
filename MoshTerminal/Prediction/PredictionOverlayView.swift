import UIKit

final class PredictionOverlayView: UIView {
    var model: PredictionRenderModel = PredictionRenderModel() {
        didSet {
            guard oldValue != model else { return }
            setNeedsDisplay()
        }
    }

    var font: UIFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet {
            guard oldValue != font else { return }
            _cellMetrics = nil
            setNeedsDisplay()
        }
    }

    private var _cellMetrics: CellMetrics?
    private var cellMetrics: CellMetrics {
        if let cached = _cellMetrics {
            return cached
        }
        let metrics = CellMetrics(font: font)
        _cellMetrics = metrics
        return metrics
    }

    private struct CellMetrics {
        let cellWidth: CGFloat
        let cellHeight: CGFloat

        init(font: UIFont) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let charSize = "M".size(withAttributes: attributes)
            self.cellWidth = ceil(charSize.width)
            self.cellHeight = ceil(charSize.height)
        }
    }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard model.showPredictions else { return }

        let metrics = cellMetrics
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        for (rowIndex, rowState) in model.overlayRows.enumerated() {
            guard !rowState.unknownRow else { continue }

            for cell in rowState.cells where cell.active {
                let x = CGFloat(cell.col) * metrics.cellWidth
                let y = CGFloat(rowIndex) * metrics.cellHeight

                if let replacement = cell.replacement {
                    let string = String(replacement.char)
                    string.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)

                    if model.underlinePredictions {
                        let underlineY = y + metrics.cellHeight - 1
                        let path = UIBezierPath()
                        path.move(to: CGPoint(x: x, y: underlineY))
                        path.addLine(to: CGPoint(x: x + metrics.cellWidth, y: underlineY))
                        UIColor.systemOrange.setStroke()
                        path.lineWidth = 1
                        path.stroke()
                    }
                } else if cell.unknown && model.underlinePredictions {
                    let underlineY = y + metrics.cellHeight - 1
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: x, y: underlineY))
                    path.addLine(to: CGPoint(x: x + metrics.cellWidth, y: underlineY))
                    UIColor.systemOrange.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }

        for cursorPrediction in model.cursorPredictions {
            let cursorX = CGFloat(cursorPrediction.col) * metrics.cellWidth
            let cursorY = CGFloat(cursorPrediction.row) * metrics.cellHeight

            let underlineY = cursorY + metrics.cellHeight - 1
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cursorX, y: underlineY))
            path.addLine(to: CGPoint(x: cursorX + metrics.cellWidth, y: underlineY))
            UIColor.systemGreen.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}
