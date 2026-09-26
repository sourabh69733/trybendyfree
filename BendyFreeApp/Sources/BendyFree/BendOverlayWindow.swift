import AppKit
import QuartzCore

public enum BendStyle: String, CaseIterable {
    case silk = "Silk"
    case shade = "Shade"
    case frost = "Frost"
}

@MainActor
public final class BendOverlayWindow: NSWindow {
    // Visual layers
    // internal (not private) so tests can verify each style gets a distinct material/tint.
    let blurView = NSVisualEffectView()
    var shadowLayer = CAGradientLayer()
    
    // State & physics
    private var isEffectActive = false
    private var session = FoldSession()
    private var usesSensorWatchdog = true
    public var currentStyle: BendStyle = .silk {
        didSet { updateMaterial() }
    }
    public var onStatusChange: ((String) -> Void)?
    public private(set) var status = "Ready - close the lid below 110°" {
        didSet {
            guard status != oldValue else { return }
            NSLog("[BendyFree] %@", status)
            onStatusChange?(status)
        }
    }
    
    private var targetProgress: CGFloat = 0.0
    private var currentProgress: CGFloat = 0.0
    private var displayTimer: Timer?
    
    // Safety monitors
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    public init() {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupLayers(size: screenRect.size)
    }

    private func setupLayers(size: CGSize) {
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        self.contentView = host

        // Live blur of whatever is behind the window; no Screen Recording permission needed.
        blurView.frame = host.bounds
        blurView.autoresizingMask = [.width, .height]
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.alphaValue = 0
        host.addSubview(blurView)

        shadowLayer.frame = host.bounds
        shadowLayer.locations = [0.0, 0.45, 0.85]
        shadowLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        shadowLayer.endPoint = CGPoint(x: 0.5, y: 0.15)
        shadowLayer.opacity = 0.0
        host.layer?.addSublayer(shadowLayer)

        updateMaterial() // sets blurView.material and shadowLayer.colors for currentStyle
    }

    public func updateAngle(_ angle: Double, isSimulation: Bool = false) {
        usesSensorWatchdog = !isSimulation
        guard let progress = session.progress(angle: angle, now: ProcessInfo.processInfo.systemUptime) else {
            if isEffectActive { hideEffect() }
            if !session.isSuppressed { status = "Ready - close the lid below 110°" }
            return
        }
        targetProgress = CGFloat(progress)
        if !isEffectActive { startEffect() }
    }

    private func startEffect() {
        guard !isEffectActive else { return }
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }) else {
            dismissEffect(reason: "Built-in display unavailable")
            return
        }

        isEffectActive = true
        setFrame(screen.frame, display: false)
        setupLayers(size: screen.frame.size)
        currentProgress = 0
        applyRender(progress: 0)
        setupSafetyDismissMonitors()
        orderFront(nil)
        status = "Fold effect active"
        startPhysicsLoop()
    }

    public func dismissEffect(reason: String = "Dismissed - reopen past 110° to resume") {
        session.dismiss()
        hideEffect()
        status = reason
    }

    private func hideEffect() {
        guard isEffectActive else { return }

        targetProgress = 0.0
        currentProgress = 0.0
        stopPhysicsLoop()

        self.orderOut(nil)
        isEffectActive = false

        removeSafetyDismissMonitors()
    }

    private func startPhysicsLoop() {
        stopPhysicsLoop()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickPhysics() }
        }
        RunLoop.main.add(displayTimer!, forMode: .common)
    }

    private func stopPhysicsLoop() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tickPhysics() {
        if usesSensorWatchdog && session.hasExpired(now: ProcessInfo.processInfo.systemUptime) {
            dismissEffect(reason: "Angle updates stopped - reopen the lid to resume")
            return
        }
        let delta = targetProgress - currentProgress
        if delta == 0 { return }
        if abs(delta) < 0.001 {
            currentProgress = targetProgress
            if currentProgress <= 0.0 {
                dismissEffect()
                return
            }
        } else {
            currentProgress += delta * 0.20
        }

        applyRender(progress: currentProgress)
    }

    /// Each style gets its own shadow tint, and Shade/Frost force the blur to render
    /// in its dark/light variant - but the material itself always stays
    /// `.fullScreenUI`. Switching `.material` between different kinds (e.g. adding
    /// `.hudWindow`, which expects an actual HUD panel, not a plain window) risked
    /// leaving the view's backdrop rendering stuck even after switching back;
    /// `.appearance` has no such requirement, so it is the only thing that varies.
    private func updateMaterial() {
        blurView.material = .fullScreenUI
        switch currentStyle {
        case .silk:
            blurView.appearance = nil // follow the system's current appearance
            shadowLayer.colors = [
                NSColor.black.withAlphaComponent(0.85).cgColor,
                NSColor.black.withAlphaComponent(0.40).cgColor,
                NSColor.clear.cgColor
            ]
        case .shade:
            blurView.appearance = NSAppearance(named: .darkAqua)
            shadowLayer.colors = [
                NSColor.black.withAlphaComponent(0.95).cgColor,
                NSColor.black.withAlphaComponent(0.60).cgColor,
                NSColor.clear.cgColor
            ]
        case .frost:
            blurView.appearance = NSAppearance(named: .aqua)
            shadowLayer.colors = [
                NSColor(calibratedRed: 0.75, green: 0.85, blue: 1.0, alpha: 0.55).cgColor,
                NSColor(calibratedRed: 0.75, green: 0.85, blue: 1.0, alpha: 0.20).cgColor,
                NSColor.clear.cgColor
            ]
        }
    }

    private func applyRender(progress: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        blurView.alphaValue = min(1.0, progress * 1.35)

        switch currentStyle {
        case .silk: shadowLayer.opacity = Float(progress * 0.75)
        case .shade: shadowLayer.opacity = Float(progress * 0.95)
        case .frost: shadowLayer.opacity = Float(progress * 0.40)
        }

        CATransaction.commit()
    }

    private static let escapeKeyCode: UInt16 = 53

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode { dismissEffect() }
    }

    // Escape is a deliberate "let me out" gesture, unlike an ordinary click or
    // keystroke, which the user can make anywhere on the system - in any other
    // app, on any monitor - while just doing something unrelated. Dismissing on
    // any click/key system-wide (the previous behavior) meant the effect could
    // vanish from an action that had nothing to do with it.
    private func setupSafetyDismissMonitors() {
        removeSafetyDismissMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return }
            MainActor.assumeIsolated { self?.dismissEffect() }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == Self.escapeKeyCode {
                MainActor.assumeIsolated { self?.dismissEffect() }
            }
            return event
        }
    }

    private func removeSafetyDismissMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
