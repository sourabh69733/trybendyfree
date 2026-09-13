import AppKit

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let sensor: LidSensor
    private let overlayWindow: BendOverlayWindow
    
    private var isEnabled = true
    private var angleMenuItem: NSMenuItem?
    private var effectMenuItem: NSMenuItem?
    private var slider: NSSlider?

    public init(sensor: LidSensor, overlayWindow: BendOverlayWindow) {
        self.sensor = sensor
        self.overlayWindow = overlayWindow
        super.init()

        setupStatusItem()
        overlayWindow.onStatusChange = { [weak self] _ in self?.updateEffectStatus() }
        updateEffectStatus()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = "📐 Bendy"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }

        buildMenu()
    }

    public func updateAngleDisplay(_ angle: Double) {
        let rounded = Int(angle)
        statusItem?.button?.title = "📐 \(rounded)°"
        let source = sensor.isSimulating ? "Simulated" : (sensor.isSensorAvailable ? "Hardware Sensor" : "Unavailable")
        angleMenuItem?.title = "Lid Angle: \(rounded)° (\(source))"
        
        if isEnabled {
            overlayWindow.updateAngle(angle, isSimulation: sensor.isSimulating)
        }
    }

    public func showSensorUnavailable() {
        statusItem?.button?.title = "📐 —"
        angleMenuItem?.title = "Lid sensor unavailable — effect paused"
    }

    public func menuWillOpen(_ menu: NSMenu) { updateEffectStatus() }

    private func updateEffectStatus() {
        let message: String
        if !isEnabled { message = "Effect disabled" }
        else if !CGPreflightScreenCaptureAccess() { message = "Screen Recording permission required" }
        else { message = overlayWindow.status }
        effectMenuItem?.title = message
        statusItem?.button?.toolTip = message
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let titleItem = NSMenuItem(title: "BendyFree — Desktop Fold", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        angleMenuItem = NSMenuItem(title: "Lid Angle: Detecting...", action: nil, keyEquivalent: "")
        angleMenuItem?.isEnabled = false
        menu.addItem(angleMenuItem!)
        let effectItem = NSMenuItem(title: overlayWindow.status, action: nil, keyEquivalent: "")
        effectItem.isEnabled = false
        effectMenuItem = effectItem
        menu.addItem(effectItem)

        menu.addItem(NSMenuItem.separator())

        // Emergency Reset / Dismiss button
        let resetItem = NSMenuItem(title: "Dismiss Effect (Esc)", action: #selector(dismissEffectNow), keyEquivalent: "\u{1b}")
        resetItem.target = self
        menu.addItem(resetItem)

        // Enable / Disable toggle
        let toggleItem = NSMenuItem(title: "Enable Fold Effect", action: #selector(toggleEnabled), keyEquivalent: "e")
        toggleItem.target = self
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)

        // Styles submenu
        let stylesItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let stylesSubmenu = NSMenu()
        for style in BendStyle.allCases {
            let item = NSMenuItem(title: style.rawValue, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            item.state = (overlayWindow.currentStyle == style) ? .on : .off
            stylesSubmenu.addItem(item)
        }
        stylesItem.submenu = stylesSubmenu
        menu.addItem(stylesItem)

        menu.addItem(NSMenuItem.separator())

        // Test Slider: 100° is fully open (no effect), 30° is folded
        let sliderContainer = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 54))
        let sliderLabel = NSTextField(labelWithString: "Test Fold (Slide left to test):")
        sliderLabel.frame = NSRect(x: 14, y: 28, width: 190, height: 18)
        sliderLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        let newSlider = NSSlider(value: 100, minValue: 25, maxValue: 100, target: self, action: #selector(sliderMoved(_:)))
        newSlider.frame = NSRect(x: 12, y: 4, width: 196, height: 22)
        newSlider.isContinuous = true
        self.slider = newSlider

        sliderContainer.addSubview(sliderLabel)
        sliderContainer.addSubview(newSlider)

        let testItem = NSMenuItem()
        testItem.view = sliderContainer
        menu.addItem(testItem)

        let resumeItem = NSMenuItem(title: "Resume Hardware Sensor", action: #selector(resumeHardware), keyEquivalent: "")
        resumeItem.target = self
        menu.addItem(resumeItem)
        let permissionItem = NSMenuItem(title: "Allow Screen Recording…", action: #selector(requestScreenRecording), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem.separator())

        let websiteItem = NSMenuItem(title: "Visit trybendyfree.in", action: #selector(openWebsite), keyEquivalent: "")
        websiteItem.target = self
        menu.addItem(websiteItem)

        let quitItem = NSMenuItem(title: "Quit BendyFree", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func dismissEffectNow() {
        overlayWindow.dismissEffect()
        slider?.doubleValue = 100
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        if !isEnabled {
            overlayWindow.dismissEffect()
        } else {
            // An explicit enable action should not inherit an old dismissal latch.
            overlayWindow.updateAngle(100)
            overlayWindow.updateAngle(sensor.currentAngle, isSimulation: sensor.isSimulating)
        }
        updateEffectStatus()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? BendStyle else { return }
        overlayWindow.currentStyle = style
        sender.menu?.items.forEach { $0.state = .off }
        sender.state = .on
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        if !sensor.isSimulating { overlayWindow.updateAngle(105) }
        let simulatedAngle = sender.doubleValue
        sensor.simulateAngle(simulatedAngle)
    }

    @objc private func resumeHardware() {
        overlayWindow.updateAngle(100)
        sensor.startMonitoring()
    }

    @objc private func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        if !CGPreflightScreenCaptureAccess(), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        overlayWindow.updateAngle(100)
        updateEffectStatus()
    }

    @objc private func openWebsite() {
        if let url = URL(string: "https://trybendyfree.in") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        overlayWindow.dismissEffect()
        NSApplication.shared.terminate(nil)
    }
}
