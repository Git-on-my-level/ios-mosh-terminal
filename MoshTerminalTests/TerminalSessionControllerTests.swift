import XCTest
@testable import MoshTerminal
import UIKit

final class TerminalSessionControllerTests: XCTestCase {
    private let enableSequence = Data([0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x68]) // ESC[?2004h
    private let disableSequence = Data([0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x6C]) // ESC[?2004l

    func testBracketedPasteModeDetectsAcrossSplitChunks() {
        let controller = TerminalSessionController()

        controller.feedOutput(Data(enableSequence.prefix(3)))
        XCTAssertFalse(controller.isBracketedPasteEnabled)

        controller.feedOutput(Data(enableSequence.dropFirst(3)))
        XCTAssertTrue(controller.isBracketedPasteEnabled)

        controller.feedOutput(Data(disableSequence.prefix(4)))
        XCTAssertTrue(controller.isBracketedPasteEnabled)

        controller.feedOutput(Data(disableSequence.dropFirst(4)))
        XCTAssertFalse(controller.isBracketedPasteEnabled)
    }

    func testPreparedPasteDataWrapsMultilineWhenBracketedPasteEnabled() {
        let controller = TerminalSessionController()
        controller.feedOutput(enableSequence)

        let payload = controller.preparedPasteData(from: "echo 1\necho 2\n")
        let text = String(decoding: payload, as: UTF8.self)

        XCTAssertEqual(text, "\u{1B}[200~echo 1\recho 2\r\u{1B}[201~")
    }

    func testPreparedPasteDataDoesNotWrapWhenDisabled() {
        let controller = TerminalSessionController()
        controller.feedOutput(enableSequence)
        controller.feedOutput(disableSequence)

        let payload = controller.preparedPasteData(from: "echo 1\necho 2\n")
        let text = String(decoding: payload, as: UTF8.self)

        XCTAssertEqual(text, "echo 1\recho 2\r")
    }

    func testPreparedPasteDataDoesNotWrapSingleLineWhenEnabled() {
        let controller = TerminalSessionController()
        controller.feedOutput(enableSequence)

        let payload = controller.preparedPasteData(from: "echo hello")
        let text = String(decoding: payload, as: UTF8.self)

        XCTAssertEqual(text, "echo hello")
    }

    func testBracketedPasteModeDetectsMarkerWithinLargeChunk() {
        let controller = TerminalSessionController()
        var output = Data(repeating: UInt8(ascii: "x"), count: 80)
        output.append(enableSequence)
        output.append(Data(repeating: UInt8(ascii: "y"), count: 10))

        controller.feedOutput(output)

        XCTAssertTrue(controller.isBracketedPasteEnabled)
    }

    func testBracketedPasteModeUsesLastMarkerWhenChunkContainsBoth() {
        let controller = TerminalSessionController()
        var output = Data(repeating: UInt8(ascii: "z"), count: 16)
        output.append(enableSequence)
        output.append(Data(repeating: UInt8(ascii: "q"), count: 4))
        output.append(disableSequence)
        output.append(Data(repeating: UInt8(ascii: "w"), count: 4))

        controller.feedOutput(output)

        XCTAssertFalse(controller.isBracketedPasteEnabled)
    }

    func testAltPrefixesPrintableInputWithEscapeWhenEnabled() {
        let controller = TerminalSessionController()
        controller.isAltActive = true
        let source = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        )

        var captured: Data?
        controller.onInput = { captured = $0 }

        controller.send(source: source, data: [UInt8(ascii: "f")][...])

        XCTAssertEqual(captured, Data([0x1B, UInt8(ascii: "f")]))
    }

    func testAltDoesNotTransformInputWhenDisabled() {
        let controller = TerminalSessionController()
        let source = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        )

        var captured: Data?
        controller.onInput = { captured = $0 }

        controller.send(source: source, data: [UInt8(ascii: "f")][...])

        XCTAssertEqual(captured, Data([UInt8(ascii: "f")]))
    }

    func testAltIgnoresNonPrintableSingleByte() {
        let controller = TerminalSessionController()
        controller.isAltActive = true
        let source = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        )

        var captured: Data?
        controller.onInput = { captured = $0 }

        controller.send(source: source, data: [0x09][...]) // tab

        XCTAssertEqual(captured, Data([0x09]))
    }

    func testCtrlTransformationStillTakesPrecedenceOverAlt() {
        let controller = TerminalSessionController()
        controller.isCtrlActive = true
        controller.isAltActive = true
        let source = TerminalUIKitView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        )

        var captured: Data?
        controller.onInput = { captured = $0 }

        controller.send(source: source, data: [UInt8(ascii: "f")][...])

        XCTAssertEqual(captured, Data([0x06])) // Ctrl+F
    }
}
