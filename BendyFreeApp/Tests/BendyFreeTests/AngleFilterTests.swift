import XCTest
@testable import BendyFree

final class AngleFilterTests: XCTestCase {
    func testFirstReadingPassesThroughUnchanged() {
        var filter = AngleFilter()
        XCTAssertEqual(filter.filter(80), 80)
    }

    func testSubsequentReadingsAreSmoothed() {
        var filter = AngleFilter()
        _ = filter.filter(100)
        XCTAssertEqual(filter.filter(80), 90, accuracy: 0.0001)
        XCTAssertEqual(filter.filter(80), 85, accuracy: 0.0001)
    }

    func testSmoothingConvergesOnSteadyInput() {
        var filter = AngleFilter()
        _ = filter.filter(120)
        var value = 0.0
        for _ in 0..<30 { value = filter.filter(60) }
        XCTAssertEqual(value, 60, accuracy: 0.01)
    }

    func testResetForgetsHistory() {
        var filter = AngleFilter()
        _ = filter.filter(100)
        filter.reset()
        XCTAssertEqual(filter.filter(40), 40)
    }

    func testPollsSlowlyOnlyWhenLidIsFarFromFoldRange() {
        XCTAssertEqual(AngleFilter.pollInterval(for: 150, active: 0.05), AngleFilter.idleInterval)
        XCTAssertEqual(AngleFilter.pollInterval(for: FoldSession.startAngle + 5, active: 0.05), 0.05)
        XCTAssertEqual(AngleFilter.pollInterval(for: 60, active: 0.05), 0.05)
    }

    func testIdlePollingNeverSpeedsUpACallerRequestedSlowInterval() {
        XCTAssertEqual(AngleFilter.pollInterval(for: 150, active: 1.0), 1.0)
    }
}
