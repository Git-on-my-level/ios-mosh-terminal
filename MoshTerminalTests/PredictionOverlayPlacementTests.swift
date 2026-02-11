import Prediction
import XCTest
@testable import MoshTerminal

final class PredictionOverlayPlacementTests: XCTestCase {
    @MainActor
    func testOverlayIsSubviewOfTerminalView() {
        let controller = TerminalSessionController()
        let terminalView = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        )

        let overlay = installPredictionOverlay(in: terminalView, controller: controller)

        XCTAssertTrue(terminalView.subviews.contains(overlay))
        XCTAssertEqual(overlay.superview, terminalView)
        XCTAssertTrue(terminalView.subviews.last === overlay)
    }

    @MainActor
    func testOverlayInstallIsIdempotent() {
        let controller = TerminalSessionController()
        let terminalView = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        )

        let first = installPredictionOverlay(in: terminalView, controller: controller)
        let second = installPredictionOverlay(in: terminalView, controller: controller)

        XCTAssertTrue(first === second)
        XCTAssertEqual(terminalView.subviews.filter { $0 is PredictionOverlayView }.count, 1)
    }
}
