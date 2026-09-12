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
}
