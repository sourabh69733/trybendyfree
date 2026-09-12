import Foundation
import IOKit.hid

@MainActor
public protocol LidSensorDelegate: AnyObject {
    func lidSensor(_ sensor: LidSensor, didUpdateAngle angle: Double)
}

@MainActor
public final class LidSensor {
    public weak var delegate: LidSensorDelegate?

    private var hidManager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: Timer?
    
    public private(set) var currentAngle: Double = 105.0
    public private(set) var isSensorAvailable = false

    public init() {
        setupAndOpenSensor()
    }

    deinit {
        // Cleanup handled in stopMonitoring and close when app terminates
    }

    public func startMonitoring(interval: TimeInterval = 0.05) {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollAngle()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    public func simulateAngle(_ angle: Double) {
        currentAngle = max(0.0, min(180.0, angle))
        delegate?.lidSensor(self, didUpdateAngle: currentAngle)
    }

    private func setupAndOpenSensor() {
        if device != nil, isSensorAvailable { return }

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
            ],
            // General orientation sensor matching
            [
                kIOHIDVendorIDKey: 0x05AC,
                kIOHIDPrimaryUsagePageKey: 0x0020
            ]
        ]

        for criteria in matchCriteria {
            IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
            if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                    for candidate in devices {
                        if IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
                            var report = [UInt8](repeating: 0, count: 8)
                            var length = report.count
                            let res = IOHIDDeviceGetReport(candidate, kIOHIDReportTypeFeature, CFIndex(1), &report, &length)
                            
                            if res == kIOReturnSuccess && length >= 3 {
                                self.device = candidate
                                self.isSensorAvailable = true
                                NSLog("[BendyFree] Hardware lid angle sensor successfully connected.")
                                return
                            }
                            IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
                        }
                    }
                }
            }
        }
        
        isSensorAvailable = false
    }

    private func pollAngle() {
        guard let dev = device else {
            setupAndOpenSensor()
            return
        }

        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count

        let result = IOHIDDeviceGetReport(
            dev,
            kIOHIDReportTypeFeature,
            CFIndex(1),
            &report,
            &length
        )

        guard result == kIOReturnSuccess, length >= 3 else {
            // Connection lost; trigger reconnect on next poll
            self.device = nil
            self.isSensorAvailable = false
            return
        }

        let low = Int(report[1])
        let high = Int(report[2]) << 8
        let rawAngle = high | low

        // Ignore 1 (docked/clamshell) or 0
        guard rawAngle > 1 else { return }

        var angle = Double(rawAngle)
        // Normalize if sensor reports in tenths of a degree
        if angle > 180.0 && angle <= 1800.0 {
            angle = angle / 10.0
        }

        if angle >= 0.0 && angle <= 180.0 {
            currentAngle = angle
            delegate?.lidSensor(self, didUpdateAngle: currentAngle)
        }
    }

    public func close() {
        if let dev = device {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            device = nil
        }
        if let mgr = hidManager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        isSensorAvailable = false
    }
}
