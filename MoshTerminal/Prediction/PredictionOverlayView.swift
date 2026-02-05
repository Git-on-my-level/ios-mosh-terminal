import UIKit

final class PredictionOverlayView: UIView {
    var model: PredictionRenderModel = PredictionRenderModel() {
        didSet {
            scheduleRedraw()
        }
    }

    var predictionTextColor: UIColor = .label {
        didSet {
            guard oldValue != predictionTextColor else { return }
            scheduleRedraw()
        }
    }

    var predictionBackgroundColor: UIColor = .clear {
        didSet {
            guard oldValue != predictionBackgroundColor else { return }
            scheduleRedraw()
        }
    }

    var predictionUnderlineColor: UIColor = .systemOrange {
        didSet {
            guard oldValue != predictionUnderlineColor else { return }
            scheduleRedraw()
        }
    }

    var cursorUnderlineColor: UIColor = .systemGreen {
        didSet {
            guard oldValue != cursorUnderlineColor else { return }
            scheduleRedraw()
        }
    }

    var font: UIFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet {
            guard oldValue != font else { return }
            _cellMetrics = nil
            scheduleRedraw()
        }
    }

    private var _cellMetrics: CellMetrics?
    private var pendingRedraw = false
    private var redrawWorkItem: DispatchWorkItem?
    private let redrawQueue = DispatchQueue(label: "com.mosh.overlay", qos: .userInteractive)

    private let minFrameInterval: TimeInterval = 1.0 / 60.0
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

    private func scheduleRedraw() {
        guard !pendingRedraw else { return }
        pendingRedraw = true

        redrawWorkItem?.cancel()
        redrawWorkItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingRedraw = false
                self.setNeedsDisplay()
            }
        }
        redrawQueue.asyncAfter(deadline: .now() + minFrameInterval, execute: redrawWorkItem!)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // Always clear previous drawing; this view is transparent.
        context.clear(rect)
        guard model.showPredictions else { return }

        let metrics = cellMetrics
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: predictionTextColor
        ]

        for (rowIndex, rowState) in model.overlayRows.enumerated() {
            guard !rowState.unknownRow else { continue }

            for cell in rowState.cells where cell.active {
                let x = CGFloat(cell.col) * metrics.cellWidth
                let y = CGFloat(rowIndex) * metrics.cellHeight
                let cellRect = CGRect(x: x, y: y, width: metrics.cellWidth, height: metrics.cellHeight)

                if !cell.unknown {
                    predictionBackgroundColor.setFill()
                    context.fill(cellRect)
                }

                if let replacement = cell.replacement {
                    let string = String(replacement.char)
                    string.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)

                    if model.underlinePredictions {
                        let underlineY = y + metrics.cellHeight - 1
                        let path = UIBezierPath()
                        path.move(to: CGPoint(x: x, y: underlineY))
                        path.addLine(to: CGPoint(x: x + metrics.cellWidth, y: underlineY))
                        predictionUnderlineColor.setStroke()
                        path.lineWidth = 1
                        path.stroke()
                    }
                } else if cell.unknown && model.underlinePredictions {
                    let underlineY = y + metrics.cellHeight - 1
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: x, y: underlineY))
                    path.addLine(to: CGPoint(x: x + metrics.cellWidth, y: underlineY))
                    predictionUnderlineColor.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }

        if let cursorPrediction = model.cursorPredictions.last {
            let cursorX = CGFloat(cursorPrediction.col) * metrics.cellWidth
            let cursorY = CGFloat(cursorPrediction.row) * metrics.cellHeight

            let underlineY = cursorY + metrics.cellHeight - 1
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cursorX, y: underlineY))
            path.addLine(to: CGPoint(x: cursorX + metrics.cellWidth, y: underlineY))
            cursorUnderlineColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}
