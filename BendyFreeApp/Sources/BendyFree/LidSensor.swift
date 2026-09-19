import Foundation
import IOKit.hid

@MainActor
public protocol LidSensorDelegate: AnyObject {
    func lidSensor(_ sensor: LidSensor, didUpdateAngle angle: Double)
}

protocol AngleReader: AnyObject, Sendable {
    func readAngle() -> Double?
    func close()
}

@MainActor
public final class LidSensor {
    public weak var delegate: LidSensorDelegate?
    public var onUnavailable: (() -> Void)?
    public private(set) var currentAngle = 120.0
    public private(set) var isSensorAvailable = false
    public private(set) var isSimulating = false

    private let queue = DispatchQueue(label: "in.trybendyfree.sensor", qos: .utility)
    private let reader: AngleReader
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var filter = AngleFilter()
    private var reportedUnavailable = false
    private var pollInterval: TimeInterval = 0.05

    public convenience init() { self.init(reader: HIDAngleReader()) }

    init(reader: AngleReader) { self.reader = reader }

    public func startMonitoring(interval: TimeInterval = 0.05) {
        stopMonitoring()
        isSimulating = false
        let fastInterval = max(0.02, interval)
        pollInterval = fastInterval
        let activeGeneration = generation
        let reader = self.reader
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: fastInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            let angle = reader.readAngle()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == activeGeneration else { return }
                guard let angle, angle.isFinite, (0...180).contains(angle) else {
                    self.isSensorAvailable = false
                    self.filter.reset()
                    // Report the transition once, not on every poll.
                    if !self.reportedUnavailable {
                        self.reportedUnavailable = true
                        self.onUnavailable?()
                    }
                    return
                }
                self.reportedUnavailable = false
                self.isSensorAvailable = true
                let smoothed = self.filter.filter(angle)
                self.currentAngle = smoothed
                self.delegate?.lidSensor(self, didUpdateAngle: smoothed)
                self.adjustPolling(for: smoothed, fastInterval: fastInterval)
            }
        }
        self.timer = timer
        timer.resume()
    }

    /// Poll slowly while the lid is comfortably open to save battery.
    private func adjustPolling(for angle: Double, fastInterval: TimeInterval) {
        let desired = AngleFilter.pollInterval(for: angle, active: fastInterval)
        guard desired != pollInterval, let timer else { return }
        pollInterval = desired
        timer.schedule(deadline: .now() + desired, repeating: desired, leeway: .milliseconds(5))
    }

    public func stopMonitoring() {
        generation += 1
        filter.reset()
        reportedUnavailable = false
        timer?.cancel()
        timer = nil
        isSensorAvailable = false
        let reader = self.reader
        // Serialized with reads; shutdown never waits for a stuck hardware call.
        queue.async { reader.close() }
    }

    public func simulateAngle(_ angle: Double) {
        if !isSimulating {
            stopMonitoring()
            isSimulating = true
        }
        guard angle.isFinite else { return }
        currentAngle = max(0, min(180, angle))
        delegate?.lidSensor(self, didUpdateAngle: currentAngle)
    }

    public func close() { stopMonitoring() }
}

/// All IOKit calls and handles are confined to LidSensor's serial worker queue.
private final class HIDAngleReader: AngleReader, @unchecked Sendable {
    private var hidManager: IOHIDManager?
    private var device: IOHIDDevice?
    private var nextDiscovery: TimeInterval = 0
    private var loggedDiagnostics = false

    /// Diagnostics are logged once per failure episode so retries don't flood the log.
    private func diag(_ message: String) {
        guard !loggedDiagnostics else { return }
        NSLog("[BendyFree] %@", message)
    }

    private func setupAndOpenSensor() {
        if device != nil { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        let matchCriteria: [[String: Any]] = [
            // Standard MacBook Hinge Sensor matching
            [
                kIOHIDVendorIDKey: 0x05AC,
                kIOHIDProductIDKey: 0x8104,
                kIOHIDPrimaryUsagePageKey: 0x0020,
                kIOHIDPrimaryUsageKey: 0x008A
            ],
            // Broader Apple 0x8104 matching
            [
                kIOHIDVendorIDKey: 0x05AC,
                kIOHIDProductIDKey: 0x8104
            ]
        ]

        for criteria in matchCriteria {
            IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if openResult != kIOReturnSuccess {
                diag(String(format: "IOHIDManagerOpen failed: 0x%x", openResult))
            } else {
                let found = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0
                diag("HID matching found \(found) device(s)")
                if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                    for candidate in devices {
                        if IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                            var report = [UInt8](repeating: 0, count: 8)
                            var length = report.count
                            let res = IOHIDDeviceGetReport(candidate, kIOHIDReportTypeFeature, CFIndex(1), &report, &length)

                            diag(String(format: "GetReport result=0x%x length=%d bytes=", res, length) + report.map { String($0) }.joined(separator: ","))
                            if res == kIOReturnSuccess && length >= 3 && report[0] == 1 {
                                self.device = candidate

                                NSLog("[BendyFree] Hardware lid angle sensor successfully connected.")
                                loggedDiagnostics = false
                                return
                            }
                            IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
                        }
                    }
                }
            }
        }

        loggedDiagnostics = true
        close()
    }

    func readAngle() -> Double? {
        if device == nil {
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= nextDiscovery else { return nil }
            nextDiscovery = now + 2
            setupAndOpenSensor()
        }
        guard let device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3, report[0] == 1 else {
            close()
            nextDiscovery = ProcessInfo.processInfo.systemUptime + 2
            return nil
        }
        // Preserve the existing decoder until raw reports can be checked on hardware.
        let raw = Int(report[1]) | (Int(report[2]) << 8)
        var angle = Double(raw)
        if angle > 180, angle <= 1800 { angle /= 10 }
        return (0...180).contains(angle) ? angle : nil
    }

    func close() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        if let hidManager { IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        hidManager = nil
    }
}
