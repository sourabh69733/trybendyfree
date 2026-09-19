import XCTest
@testable import BendyFree

final class LidSensorTests: XCTestCase {
    @MainActor
    func testSlowHardwareDoesNotBlockUIOrOverwriteSimulation() async {
        let started = expectation(description: "hardware read started")
        let finished = expectation(description: "hardware read returned")
        let reader = BlockingReader(started: started, finished: finished)
        let sensor = LidSensor(reader: reader)
        let delegate = RecordingDelegate()
        sensor.delegate = delegate
        sensor.startMonitoring()

        await fulfillment(of: [started], timeout: 2)
        // This must remain usable while the hardware read is blocked.
        sensor.simulateAngle(60)
        XCTAssertTrue(sensor.isSimulating)
        XCTAssertEqual(delegate.angles, [60])

        reader.release.signal()
        await fulfillment(of: [finished], timeout: 2)
        // Drain the main queue after the worker has returned its obsolete reading.
        let drained = expectation(description: "pending result delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 1)
        XCTAssertEqual(delegate.angles, [60])
        XCTAssertEqual(sensor.currentAngle, 60)
        sensor.close()
    }
}

private final class BlockingReader: AngleReader, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    let started: XCTestExpectation
    let finished: XCTestExpectation

    init(started: XCTestExpectation, finished: XCTestExpectation) {
        self.started = started
        self.finished = finished
    }

    func readAngle() -> Double? {
        XCTAssertFalse(Thread.isMainThread, "HID reads must never block the UI thread")
        started.fulfill()
        XCTAssertEqual(release.wait(timeout: .now() + 3), .success)
        finished.fulfill()
        return 70
    }

    func close() {
        XCTAssertFalse(Thread.isMainThread, "Hardware cleanup must not block the UI")
    }
}

@MainActor
private final class RecordingDelegate: LidSensorDelegate {
    var angles: [Double] = []
    func lidSensor(_ sensor: LidSensor, didUpdateAngle angle: Double) {
        angles.append(angle)
    }
}

extension LidSensorTests {
    @MainActor
    func testUnavailableIsReportedOnceNotOnEveryPoll() async {
        let sensor = LidSensor(reader: ScriptedReader(readings: []))
        var reports = 0
        sensor.onUnavailable = { reports += 1 }
        sensor.startMonitoring(interval: 0.02)

        try? await Task.sleep(nanoseconds: 400_000_000)
        sensor.close()
        XCTAssertEqual(reports, 1)
        XCTAssertFalse(sensor.isSensorAvailable)
    }

    @MainActor
    func testReadingsAreSmoothedBeforeReachingDelegate() async {
        let sensor = LidSensor(reader: ScriptedReader(readings: [100, 80]))
        let delegate = RecordingDelegate()
        sensor.delegate = delegate
        sensor.startMonitoring(interval: 0.02)

        try? await Task.sleep(nanoseconds: 300_000_000)
        sensor.close()
        XCTAssertEqual(delegate.angles.first, 100)
        XCTAssertEqual(delegate.angles.dropFirst().first ?? 0, 90, accuracy: 0.0001)
    }
}

/// Returns the scripted readings in order, then nil (sensor lost) or repeats the last one.
private final class ScriptedReader: AngleReader, @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [Double]
    private var last: Double?

    init(readings: [Double]) {
        self.readings = readings
        self.last = readings.last
    }

    func readAngle() -> Double? {
        lock.lock(); defer { lock.unlock() }
        if !readings.isEmpty { return readings.removeFirst() }
        return last
    }

    func close() {}
}
