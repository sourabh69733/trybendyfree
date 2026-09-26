import XCTest
@testable import BendyFree

@MainActor
final class MenuBarControllerTests: XCTestCase {
    private func makeController() -> (MenuBarController, LidSensor) {
        let sensor = LidSensor()
        let overlay = BendOverlayWindow()
        let controller = MenuBarController(sensor: sensor, overlayWindow: overlay)
        return (controller, sensor)
    }

    func testResumeItemStartsDisabledWithNothingToResume() {
        let (controller, _) = makeController()
        XCTAssertFalse(controller.resumeItem?.isEnabled ?? true)
    }

    func testMovingTheSliderEnablesResume() {
        let (controller, sensor) = makeController()
        controller.slider?.doubleValue = 40
        controller.perform(Selector(("sliderMoved:")), with: controller.slider)
        XCTAssertTrue(sensor.isSimulating)
        XCTAssertTrue(controller.resumeItem?.isEnabled ?? false)
    }

    // The exact bug reported: after testing at some angle, "Resume Hardware
    // Sensor" must put the slider back to 120 and disable itself again -
    // otherwise the slider is left showing a stale, misleading position.
    func testResumeHardwarePutsSliderBackAndDisablesItself() {
        let (controller, sensor) = makeController()
        controller.slider?.doubleValue = 40
        controller.perform(Selector(("sliderMoved:")), with: controller.slider)

        controller.perform(Selector(("resumeHardware")))

        XCTAssertFalse(sensor.isSimulating)
        XCTAssertEqual(controller.slider?.doubleValue, 120)
        XCTAssertFalse(controller.resumeItem?.isEnabled ?? true)
    }
}
