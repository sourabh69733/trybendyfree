import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, LidSensorDelegate {
    private var sensor: LidSensor!
    private var overlayWindow: BendOverlayWindow!
    private var menuBarController: MenuBarController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background menu-bar accessory app (no dock icon clutter)
        NSApp.setActivationPolicy(.accessory)

        sensor = LidSensor()
        sensor.delegate = self

        overlayWindow = BendOverlayWindow()
        menuBarController = MenuBarController(sensor: sensor, overlayWindow: overlayWindow)
        sensor.onUnavailable = { [weak self] in
            self?.overlayWindow.dismissEffect(reason: "Lid sensor unavailable")
            self?.menuBarController.showSensorUnavailable()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Start reading hardware sensor
        sensor.startMonitoring()

        // Initial angle update
        menuBarController.updateAngleDisplay(sensor.currentAngle)
    }

    public func lidSensor(_ sensor: LidSensor, didUpdateAngle angle: Double) {
        menuBarController.updateAngleDisplay(angle)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        sensor.stopMonitoring()
        sensor.close()
        overlayWindow.dismissEffect()
    }

    @objc private func willSleep() {
        overlayWindow.dismissEffect()
        sensor.stopMonitoring()
    }

    @objc private func didWake() { sensor.startMonitoring() }

    @objc private func displayChanged() { overlayWindow.dismissEffect() }
}
