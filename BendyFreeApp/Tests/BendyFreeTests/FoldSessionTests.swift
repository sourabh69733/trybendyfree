import XCTest
@testable import BendyFree

final class FoldSessionTests: XCTestCase {
    func testDismissalSurvivesFurtherClosedLidReadings() {
        var session = FoldSession()
        XCTAssertNotNil(session.progress(angle: 70, now: 0))
        session.dismiss()
        XCTAssertNil(session.progress(angle: 69, now: 0.05))
        XCTAssertNil(session.progress(angle: 40, now: 1))
        XCTAssertNil(session.progress(angle: 130, now: 2))
        XCTAssertNotNil(session.progress(angle: 70, now: 3))
    }

    func testSlowCloseRemainsActiveWhileSensorIsReporting() {
        var session = FoldSession()
        for index in 0...199 {
            _ = session.progress(angle: 70, now: Double(index) * 0.05)
        }
        XCTAssertFalse(session.hasExpired(now: 10))
        XCTAssertTrue(session.hasExpired(now: 12))
        XCTAssertFalse(session.hasExpired(now: 10.9))
    }

    func testNormalWorkingAngleDoesNotStartAnInvisibleSession() {
        var session = FoldSession()
        XCTAssertNil(session.progress(angle: 120, now: 0))
        XCTAssertNil(session.progress(angle: 120, now: 10))
        XCTAssertNotNil(session.progress(angle: 70, now: 11))
    }

    func testNormalOpeningRearmsAfterDismissal() {
        var session = FoldSession()
        _ = session.progress(angle: 70, now: 0)
        session.dismiss()
        XCTAssertNil(session.progress(angle: 120, now: 1))
        XCTAssertNotNil(session.progress(angle: 60, now: 2))
    }

    func testInvalidReadingsCannotActivateEffect() {
        for angle in [Double.nan, Double.infinity, -1, 181] {
            var session = FoldSession()
            XCTAssertNil(session.progress(angle: angle, now: 0))
        }
    }

    func testReopeningEndsSessionAndAllowsNextClose() {
        var session = FoldSession()
        XCTAssertEqual(session.progress(angle: 70, now: 0), 0.5)
        XCTAssertNil(session.progress(angle: 130, now: 1))
        XCTAssertFalse(session.hasExpired(now: 10))
        XCTAssertEqual(session.progress(angle: 20, now: 11), 1)
    }
}
