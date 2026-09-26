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

extension BendOverlayWindowTests {
    func testEachStyleGetsADistinctMaterial() {
        let window = BendOverlayWindow()
        var materials: [BendStyle: NSVisualEffectView.Material] = [:]
        for style in BendStyle.allCases {
            window.currentStyle = style
            materials[style] = window.blurView.material
        }
        XCTAssertEqual(Set(materials.values).count, BendStyle.allCases.count, "each style should look distinct, not share a material")
    }

    func testEachStyleGetsADistinctShadowTint() {
        let window = BendOverlayWindow()
        var firstColors: [BendStyle: [CGColor]] = [:]
        for style in BendStyle.allCases {
            window.currentStyle = style
            firstColors[style] = window.shadowLayer.colors as? [CGColor]
        }
        XCTAssertEqual(firstColors[.silk]?.first, firstColors[.silk]?.first)
        XCTAssertNotEqual(firstColors[.frost]?.first, firstColors[.silk]?.first, "Frost should not look identical to Silk")
        XCTAssertNotEqual(firstColors[.shade]?.first, firstColors[.silk]?.first, "Shade should not look identical to Silk")
    }

    func testSelectingAStyleWhileEffectIsOpenUpdatesImmediately() {
        let window = BendOverlayWindow()
        window.currentStyle = .frost
        let frostMaterial = window.blurView.material
        window.currentStyle = .shade
        XCTAssertNotEqual(window.blurView.material, frostMaterial)
    }
}
