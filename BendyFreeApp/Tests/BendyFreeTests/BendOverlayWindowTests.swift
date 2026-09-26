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
    // The material is deliberately the SAME (.fullScreenUI) for every style - only
    // appearance and shadow tint vary. A different material per style (e.g.
    // .hudWindow, which expects an actual HUD panel) risked leaving the blur
    // stuck even after switching back to Silk.
    func testMaterialStaysFullScreenUIForEveryStyle() {
        let window = BendOverlayWindow()
        for style in BendStyle.allCases {
            window.currentStyle = style
            XCTAssertEqual(window.blurView.material, .fullScreenUI)
        }
    }

    func testEachStyleGetsADistinctAppearance() {
        let window = BendOverlayWindow()
        window.currentStyle = .silk
        XCTAssertNil(window.blurView.appearance, "Silk should follow the system appearance")
        window.currentStyle = .shade
        XCTAssertEqual(window.blurView.appearance?.name, .darkAqua)
        window.currentStyle = .frost
        XCTAssertEqual(window.blurView.appearance?.name, .aqua)
    }

    func testEachStyleGetsADistinctShadowTint() {
        let window = BendOverlayWindow()
        var firstColors: [BendStyle: [CGColor]] = [:]
        for style in BendStyle.allCases {
            window.currentStyle = style
            firstColors[style] = window.shadowLayer.colors as? [CGColor]
        }
        XCTAssertNotEqual(firstColors[.frost]?.first, firstColors[.silk]?.first, "Frost should not look identical to Silk")
        XCTAssertNotEqual(firstColors[.shade]?.first, firstColors[.silk]?.first, "Shade should not look identical to Silk")
    }

    func testSelectingAStyleWhileEffectIsOpenUpdatesImmediately() {
        let window = BendOverlayWindow()
        window.currentStyle = .frost
        let frostAppearance = window.blurView.appearance
        window.currentStyle = .shade
        XCTAssertNotEqual(window.blurView.appearance, frostAppearance)
    }

    // The exact bug reported: switch away to Frost/Shade, then back to Silk,
    // and Silk must render identically to how it did before any switching.
    func testSwitchingAwayAndBackToSilkRestoresItExactly() {
        let window = BendOverlayWindow()
        let originalAppearance = window.blurView.appearance
        let originalMaterial = window.blurView.material
        let originalColors = window.shadowLayer.colors as? [CGColor]

        window.currentStyle = .frost
        window.currentStyle = .shade
        window.currentStyle = .silk

        XCTAssertEqual(window.blurView.appearance, originalAppearance)
        XCTAssertEqual(window.blurView.material, originalMaterial)
        XCTAssertEqual(window.shadowLayer.colors as? [CGColor], originalColors)
    }
}

extension BendOverlayWindowTests {
    // The exact bug reported: any click or keystroke anywhere on the system
    // (not just this app) used to dismiss the effect. Only Escape should.
    func testOnlyEscapeDismissesNotAnyKey() {
        let window = BendOverlayWindow()
        window.updateAngle(60)
        XCTAssertEqual(window.status, "Fold effect active")

        let letterA = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        )!
        window.keyDown(with: letterA)
        XCTAssertEqual(window.status, "Fold effect active", "an ordinary keystroke must not dismiss the effect")

        let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        )!
        window.keyDown(with: escape)
        XCTAssertNotEqual(window.status, "Fold effect active", "Escape should dismiss the effect")
    }
}
