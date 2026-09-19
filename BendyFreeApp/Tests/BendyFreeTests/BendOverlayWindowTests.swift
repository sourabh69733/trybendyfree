import XCTest
@testable import BendyFree

@MainActor
final class BendOverlayWindowTests: XCTestCase {
    func testStartsReadyAndInactive() {
        let window = BendOverlayWindow()
        XCTAssertTrue(window.status.hasPrefix("Ready"))
        XCTAssertFalse(window.isVisible)
    }

    func testOpenLidReadingKeepsOverlayHidden() {
        let window = BendOverlayWindow()
        window.updateAngle(130)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window.status.hasPrefix("Ready"))
    }

    func testDismissalLatchesUntilLidReopens() {
        let window = BendOverlayWindow()
        window.dismissEffect(reason: "Dismissed - test")
        window.updateAngle(60)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.status, "Dismissed - test")

        window.updateAngle(130)
        XCTAssertTrue(window.status.hasPrefix("Ready"))
    }

    func testDismissReasonIsShownInStatus() {
        let window = BendOverlayWindow()
        window.dismissEffect(reason: "Lid sensor unavailable")
        XCTAssertEqual(window.status, "Lid sensor unavailable")
        XCTAssertFalse(window.isVisible)
    }

    func testStatusChangesAreReported() {
        let window = BendOverlayWindow()
        var messages: [String] = []
        window.onStatusChange = { messages.append($0) }
        window.dismissEffect(reason: "One")
        window.dismissEffect(reason: "One")
        window.dismissEffect(reason: "Two")
        XCTAssertEqual(messages, ["One", "Two"])
    }

    func testInvalidReadingDismissesWithoutShowing() {
        let window = BendOverlayWindow()
        window.updateAngle(.nan)
        XCTAssertFalse(window.isVisible)
    }
}
