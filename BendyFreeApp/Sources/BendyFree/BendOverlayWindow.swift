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
    private let blurView = NSVisualEffectView()
    private let blurMaskLayer = CAGradientLayer()
    private var shadowLayer = CAGradientLayer()
    
    // State & physics
    private var isEffectActive = false
    private var session = FoldSession()
    private var usesSensorWatchdog = true
    public var currentStyle: BendStyle = .silk
    public var onStatusChange: ((String) -> Void)?
    public private(set) var status = "Ready - close the lid below 90°" {
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
        blurView.material = .fullScreenUI
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.alphaValue = 0
        // Progressive blur: strong at the top (screen far edge), crisp near the keyboard.
        blurMaskLayer.frame = host.bounds
        blurMaskLayer.colors = [
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0.8).cgColor,
            NSColor.clear.cgColor
        ]
        blurMaskLayer.locations = [0.0, 0.50, 0.85]
        blurMaskLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        blurMaskLayer.endPoint = CGPoint(x: 0.5, y: 0.10)
        blurView.layer?.mask = blurMaskLayer
        host.addSubview(blurView)

        shadowLayer.frame = host.bounds
        shadowLayer.colors = [
            NSColor.black.withAlphaComponent(0.85).cgColor,
            NSColor.black.withAlphaComponent(0.40).cgColor,
            NSColor.clear.cgColor
        ]
        shadowLayer.locations = [0.0, 0.45, 0.85]
        shadowLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        shadowLayer.endPoint = CGPoint(x: 0.5, y: 0.15)
        shadowLayer.opacity = 0.0
        host.layer?.addSublayer(shadowLayer)
    }

    public func updateAngle(_ angle: Double, isSimulation: Bool = false) {
        usesSensorWatchdog = !isSimulation
        guard let progress = session.progress(angle: angle, now: ProcessInfo.processInfo.systemUptime) else {
            if isEffectActive { hideEffect() }
            if !session.isSuppressed { status = "Ready - close the lid below 90°" }
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

    public func dismissEffect(reason: String = "Dismissed - reopen to 90° to resume") {
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

    public override func mouseDown(with event: NSEvent) {
        dismissEffect()
    }

    public override func rightMouseDown(with event: NSEvent) {
        dismissEffect()
    }

    public override func keyDown(with event: NSEvent) {
        dismissEffect()
    }

    private func setupSafetyDismissMonitors() {
        removeSafetyDismissMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissEffect() }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissEffect() }
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
