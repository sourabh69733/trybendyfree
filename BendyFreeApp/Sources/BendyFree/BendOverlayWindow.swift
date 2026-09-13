import AppKit
import QuartzCore
import CoreImage

public enum BendStyle: String, CaseIterable {
    case silk = "Silk"
    case shade = "Shade"
    case frost = "Frost"
}

@MainActor
public final class BendOverlayWindow: NSWindow {
    // Visual layers
    private var contentContainerLayer = CALayer()
    private var sharpLayer = CALayer()
    private var blurLayer = CALayer()
    private var blurMaskLayer = CAGradientLayer()
    private var shadowLayer = CAGradientLayer()
    private var featherMaskLayer = CAGradientLayer()
    
    // State & physics
    private var isEffectActive = false
    private var session = FoldSession()
    private var captureGeneration = 0
    private var usesSensorWatchdog = true
    public var currentStyle: BendStyle = .silk
    public var onStatusChange: ((String) -> Void)?
    public private(set) var status = "Ready — close the lid below 90°" {
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
    private var captureTimeoutTimer: Timer?

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
        guard let contentView = self.contentView else { return }
        contentView.wantsLayer = true
        guard let rootLayer = contentView.layer else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Root 3D perspective
        var sublayerTransform = CATransform3DIdentity
        sublayerTransform.m34 = -1.0 / 1400.0
        rootLayer.sublayerTransform = sublayerTransform

        // 3D Content Container: Hinge anchored at the bottom
        contentContainerLayer.bounds = CGRect(origin: .zero, size: size)
        contentContainerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        contentContainerLayer.position = CGPoint(x: size.width / 2.0, y: 0.0)

        // 1. Sharp Base Desktop Layer
        sharpLayer.bounds = CGRect(origin: .zero, size: size)
        sharpLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sharpLayer.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        sharpLayer.contentsScale = scale
        sharpLayer.contentsGravity = .resize

        // 2. Soft Progressive Blur Layer
        blurLayer.bounds = CGRect(origin: .zero, size: size)
        blurLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        blurLayer.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        blurLayer.contentsScale = scale
        blurLayer.contentsGravity = .resize
        blurLayer.opacity = 0.0

        // Progressive Blur Mask: Top 70% blurs deeply, bottom 30% near keyboard stays crisp
        blurMaskLayer.bounds = CGRect(origin: .zero, size: size)
        blurMaskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        blurMaskLayer.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        blurMaskLayer.colors = [
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0.8).cgColor,
            NSColor.clear.cgColor
        ]
        blurMaskLayer.locations = [0.0, 0.50, 0.85]
        blurMaskLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        blurMaskLayer.endPoint = CGPoint(x: 0.5, y: 0.10)
        blurLayer.mask = blurMaskLayer

        // 3. Ambient & Vignette Shadow Layer
        shadowLayer.bounds = CGRect(origin: .zero, size: size)
        shadowLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        shadowLayer.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        shadowLayer.colors = [
            NSColor.black.withAlphaComponent(0.85).cgColor,
            NSColor.black.withAlphaComponent(0.40).cgColor,
            NSColor.clear.cgColor
        ]
        shadowLayer.locations = [0.0, 0.45, 0.85]
        shadowLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        shadowLayer.endPoint = CGPoint(x: 0.5, y: 0.15)
        shadowLayer.opacity = 0.0

        // 4. Soft Top Edge Feathering
        featherMaskLayer.bounds = CGRect(origin: .zero, size: size)
        featherMaskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        featherMaskLayer.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        featherMaskLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.cgColor,
            NSColor.white.cgColor
        ]
        featherMaskLayer.locations = [0.0, 0.06, 1.0]
        featherMaskLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        featherMaskLayer.endPoint = CGPoint(x: 0.5, y: 0.0)

        // Assembly
        contentContainerLayer.addSublayer(sharpLayer)
        contentContainerLayer.addSublayer(blurLayer)
        contentContainerLayer.addSublayer(shadowLayer)
        contentContainerLayer.mask = featherMaskLayer

        rootLayer.addSublayer(contentContainerLayer)
    }

    public func updateAngle(_ angle: Double, isSimulation: Bool = false) {
        usesSensorWatchdog = !isSimulation
        guard let progress = session.progress(angle: angle, now: ProcessInfo.processInfo.systemUptime) else {
            if isEffectActive { hideEffect() }
            if !session.isSuppressed { status = "Ready — close the lid below 90°" }
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
        }), let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            dismissEffect(reason: "Built-in display unavailable")
            return
        }

        // Track preparation as active so repeated sensor readings cannot queue captures.
        isEffectActive = true
        status = "Preparing screen capture…"
        captureGeneration += 1
        let generation = captureGeneration
        setFrame(screen.frame, display: false)
        setupLayers(size: screen.frame.size)
        currentProgress = 0
        applyRender(progress: 0)
        setupSafetyDismissMonitors()
        startCaptureTimeout()

        ScreenCapture.capture(displayID: displayNumber.uint32Value) { [weak self] result in
            guard let self, self.isEffectActive, self.captureGeneration == generation else { return }
            let snapshot: DesktopSnapshot
            switch result {
            case .success(let captured): snapshot = captured
            case .failure(let failure):
                self.dismissEffect(reason: failure.message)
                return
            }
            self.captureTimeoutTimer?.invalidate()
            self.captureTimeoutTimer = nil
            self.sharpLayer.contents = snapshot.sharp
            self.blurLayer.contents = snapshot.blurred
            self.orderFront(nil)
            self.status = "Fold effect active"
            self.startPhysicsLoop()
        }
    }

    public func dismissEffect(reason: String = "Dismissed — reopen to 90° to resume") {
        session.dismiss()
        hideEffect()
        status = reason
    }

    private func hideEffect() {
        captureGeneration += 1
        guard isEffectActive else { return }

        targetProgress = 0.0
        currentProgress = 0.0
        stopPhysicsLoop()

        self.orderOut(nil)
        sharpLayer.contents = nil
        blurLayer.contents = nil
        isEffectActive = false

        removeSafetyDismissMonitors()
        captureTimeoutTimer?.invalidate()
        captureTimeoutTimer = nil
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
            dismissEffect(reason: "Angle updates stopped — reopen the lid to resume")
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

        // 1. Subtle, natural 3D tilt (max 38° so desktop doesn't tumble away)
        let maxTiltAngle = 38.0 * .pi / 180.0
        let tilt = progress * maxTiltAngle

        var transform = CATransform3DIdentity
        transform = CATransform3DRotate(transform, tilt, 1.0, 0.0, 0.0)
        contentContainerLayer.transform = transform

        // 2. Heavy progressive blur cross-fade
        // At 50% fold, blur is already deeply visible
        let blurAlpha = min(1.0, progress * 1.35)
        blurLayer.opacity = Float(blurAlpha)

        // 3. Dynamic top-edge feathering
        let feather = NSNumber(value: Float(min(0.25, 0.04 + progress * 0.16)))
        featherMaskLayer.locations = [0.0, feather, 1.0]

        // 4. Style-dependent shadow intensity
        switch currentStyle {
        case .silk:
            shadowLayer.opacity = Float(progress * 0.75)
        case .shade:
            shadowLayer.opacity = Float(progress * 0.95)
        case .frost:
            shadowLayer.opacity = Float(progress * 0.40)
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

    private func startCaptureTimeout() {
        captureTimeoutTimer?.invalidate()
        captureTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissEffect(reason: "Screen capture timed out — reopen the lid to retry") }
        }
        RunLoop.main.add(captureTimeoutTimer!, forMode: .common)
    }
}
