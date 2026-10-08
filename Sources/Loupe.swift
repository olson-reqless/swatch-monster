import AppKit
import CoreGraphics
import ScreenCaptureKit

/// A custom magnifier that replaces `NSColorSampler` so we can control zoom and
/// crosshair size. Holding Control jumps to precise zoom; scrolling trims the
/// base zoom; arrow keys nudge one pixel at a time.
///
/// Needs Screen Recording permission. If that isn't granted we fall back to the
/// system sampler so picking still works.
final class LoupeController: NSObject {
    static let shared = LoupeController()

    // Zoom is "screen points per captured pixel".
    static let minZoom: CGFloat = 4
    static let maxZoom: CGFloat = 48

    // One overlay per display. macOS gives each display its own Space, so a
    // single window stretched across all of them only ever shows on one.
    private var windows: [LoupeWindow] = []
    private var views: [LoupeView] = []
    private var appActivationObserver: NSObjectProtocol?
    private var completion: ((NSColor?) -> Void)?
    private var frameTimer: Timer?
    private var isCapturing = false
    private var didWarnAboutPermission = false

    private var filters: [CGDirectDisplayID: SCContentFilter] = [:]
    private var ownApplication: SCRunningApplication?
    private var fallbackSampler: NSColorSampler?

    private(set) var preciseMode = false

    var isActive: Bool { !windows.isEmpty }

    private override init() { super.init() }

    // MARK: - Entry point

    func pick(completion: @escaping (NSColor?) -> Void) {
        guard !isActive else { return }

        guard CGPreflightScreenCaptureAccess() else {
            requestPermission()
            // Keep the hot key useful until permission is granted.
            let sampler = NSColorSampler()
            fallbackSampler = sampler
            sampler.show { [weak self] color in
                self?.fallbackSampler = nil
                completion(color)
            }
            return
        }

        self.completion = completion

        Task { @MainActor in
            await self.refreshShareableContent()
            guard !self.filters.isEmpty else {
                // Capture is unavailable for some other reason — don't leave the
                // user with a dead hot key.
                self.finish(with: nil, fallBackToSystemSampler: true)
                return
            }
            self.present()
        }
    }

    private func requestPermission() {
        CGRequestScreenCaptureAccess()

        guard !didWarnAboutPermission else { return }
        didWarnAboutPermission = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Swatch Monster needs Screen Recording access"
        alert.informativeText = """
            The zoom loupe reads pixels from the screen, which macOS gates behind \
            Screen Recording permission.

            Open System Settings > Privacy & Security > Screen & System Audio \
            Recording, enable Swatch Monster, then quit and reopen the app.

            Until then, picking falls back to the macOS system loupe, which works \
            but has no zoom control.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Shareable content

    @MainActor
    private func refreshShareableContent() async {
        do {
            let content = try await SCShareableContent.current

            // Excluding our own app keeps the overlay out of its own capture —
            // otherwise the loupe magnifies itself.
            let pid = ProcessInfo.processInfo.processIdentifier
            ownApplication = content.applications.first { $0.processID == pid }
            let excluded = ownApplication.map { [$0] } ?? []

            filters.removeAll()
            for display in content.displays {
                filters[display.displayID] = SCContentFilter(
                    display: display,
                    excludingApplications: excluded,
                    exceptingWindows: []
                )
            }
        } catch {
            NSLog("Swatch Monster: could not read shareable content — \(error.localizedDescription)")
            filters.removeAll()
        }
    }

    // MARK: - Overlay lifecycle

    @MainActor
    private func present() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(with: nil, fallBackToSystemSampler: true)
            return
        }

        for screen in screens {
            let loupeView = LoupeView(controller: self)
            let overlay = LoupeWindow(contentRect: screen.frame)
            overlay.contentView = loupeView
            overlay.setFrame(screen.frame, display: false)
            windows.append(overlay)
            views.append(loupeView)
        }

        // The overlay on the cursor's display takes the keyboard (Escape, arrows,
        // Return); the rest only draw. They're non-activating panels, so they can
        // take key even when macOS declines to bring a menu-bar app forward.
        let mouse = NSEvent.mouseLocation
        let keyIndex = windows.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        for (index, overlay) in windows.enumerated() where index != keyIndex {
            overlay.orderFrontRegardless()
        }
        NSApp.activate()
        windows[keyIndex].makeKeyAndOrderFront(nil)
        windows[keyIndex].makeFirstResponder(views[keyIndex])
        NSCursor.hide()

        // Safety net: if another app comes forward, tear the overlays down rather
        // than leave invisible full-screen windows eating clicks.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ownPID else { return }
            Task { @MainActor in self?.finish(with: nil) }
        }

        preciseMode = false
        capture()

        // Event-driven updates cover cursor movement; the timer keeps the
        // magnified content live when the screen changes under a still cursor.
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0,
                                          repeats: true) { [weak self] _ in
            self?.capture()
        }
    }

    @MainActor
    func finish(with color: NSColor?, fallBackToSystemSampler: Bool = false) {
        frameTimer?.invalidate()
        frameTimer = nil

        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }

        if isActive { NSCursor.unhide() }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        preciseMode = false

        let handler = completion
        completion = nil

        if fallBackToSystemSampler {
            let sampler = NSColorSampler()
            sampler.show { picked in handler?(picked) }
            return
        }
        handler?(color)
    }

    // MARK: - Input, routed from the view

    func setPreciseMode(_ on: Bool) {
        guard preciseMode != on else { return }
        preciseMode = on
        views.forEach { $0.animateZoomChange() }
        capture()
    }

    func adjustBaseZoom(by steps: CGFloat) {
        let store = ColorStore.shared
        let next = (store.loupeZoom + steps).rounded()
        store.loupeZoom = min(max(next, LoupeController.minZoom), LoupeController.maxZoom)
        capture()
    }

    var currentZoom: CGFloat {
        let store = ColorStore.shared
        return preciseMode ? store.loupePreciseZoom : store.loupeZoom
    }

    func nudge(dx: CGFloat, dy: CGFloat) {
        let point = LoupeController.cursorInDisplaySpace()
        // Display space is y-down, so invert dy to match arrow-key intuition.
        CGWarpMouseCursorPosition(CGPoint(x: point.x + dx, y: point.y - dy))
        CGAssociateMouseAndMouseCursorPosition(1)
        capture()
    }

    func commitCurrentColor() {
        Task { @MainActor in
            finish(with: views.first?.centerColor)
        }
    }

    func cancel() {
        Task { @MainActor in
            finish(with: nil)
        }
    }

    // MARK: - Capture

    /// Cursor position in CoreGraphics global display space (origin top-left).
    static func cursorInDisplaySpace() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
    }

    func capture() {
        guard isActive, !isCapturing else { return }

        let cursor = LoupeController.cursorInDisplaySpace()
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }

        let displayID = screen.displayID
        guard let filter = filters[displayID] else { return }

        let scale = screen.backingScaleFactor
        let zoom = currentZoom

        // Odd pixel count so exactly one pixel sits dead centre under the cursor.
        var pixelsAcross = Int((LoupeView.diameter / zoom).rounded())
        if pixelsAcross % 2 == 0 { pixelsAcross += 1 }
        pixelsAcross = max(3, pixelsAcross)

        // sourceRect is in points, local to the display.
        let bounds = CGDisplayBounds(displayID)
        let sidePoints = CGFloat(pixelsAcross) / scale
        let localX = cursor.x - bounds.origin.x
        let localY = cursor.y - bounds.origin.y

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: localX - sidePoints / 2,
                                   y: localY - sidePoints / 2,
                                   width: sidePoints,
                                   height: sidePoints)
        config.width = pixelsAcross
        config.height = pixelsAcross
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best

        isCapturing = true
        SCScreenshotManager.captureImage(contentFilter: filter,
                                        configuration: config) { [weak self] image, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCapturing = false
                guard self.isActive else { return }

                if let error {
                    NSLog("Swatch Monster: capture failed — \(error.localizedDescription)")
                    return
                }
                guard let image else { return }
                for view in self.views {
                    view.update(image: image, pixelsAcross: pixelsAcross, zoom: zoom)
                }
            }
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}

// MARK: - Overlay window

/// Borderless, transparent, above everything, and never captured itself.
private final class LoupeWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        sharingType = .none
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay view

private final class LoupeView: NSView {
    static let diameter: CGFloat = 184

    private weak var controller: LoupeController?

    private var image: CGImage?
    private var pixelsAcross = 0
    private var zoom: CGFloat = 8
    private(set) var centerColor: NSColor?

    private var renderedZoom: CGFloat = 8

    init(controller: LoupeController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Model updates

    func update(image: CGImage, pixelsAcross: Int, zoom: CGFloat) {
        // Normalise into sRGB so the hex we report matches what we store, and so
        // we can read the centre pixel from a known byte layout.
        let width = pixelsAcross
        let height = pixelsAcross
        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        if let context = CGContext(data: &bytes,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            let mid = (height / 2) * width * 4 + (width / 2) * 4
            if mid + 2 < bytes.count {
                centerColor = NSColor(srgbRed: CGFloat(bytes[mid]) / 255,
                                      green: CGFloat(bytes[mid + 1]) / 255,
                                      blue: CGFloat(bytes[mid + 2]) / 255,
                                      alpha: 1)
            }
            self.image = context.makeImage() ?? image
        } else {
            self.image = image
        }

        self.pixelsAcross = pixelsAcross
        self.zoom = zoom
        needsDisplay = true
    }

    func animateZoomChange() {
        // The zoom itself snaps; this just re-renders the chrome at the new size.
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image else { return }

        let precise = controller?.preciseMode ?? false
        let mouse = NSEvent.mouseLocation
        // Only the overlay on the cursor's display draws the loupe.
        guard let window, NSMouseInRect(mouse, window.frame, false) else { return }
        let windowPoint = window.convertPoint(fromScreen: mouse)
        let center = convert(windowPoint, from: nil)

        let diameter = LoupeView.diameter
        let loupeRect = CGRect(x: center.x - diameter / 2,
                               y: center.y - diameter / 2,
                               width: diameter,
                               height: diameter)

        context.saveGState()

        // Circular magnifier, nearest-neighbour so pixels stay square.
        let circle = CGPath(ellipseIn: loupeRect, transform: nil)
        context.addPath(circle)
        context.clip()
        context.interpolationQuality = .none
        context.draw(image, in: loupeRect)

        // Pixel grid, only once blocks are big enough to be useful.
        if zoom >= 10 {
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.16).cgColor)
            context.setLineWidth(1)
            let step = diameter / CGFloat(pixelsAcross)
            var offset: CGFloat = 0
            while offset <= diameter {
                context.move(to: CGPoint(x: loupeRect.minX + offset, y: loupeRect.minY))
                context.addLine(to: CGPoint(x: loupeRect.minX + offset, y: loupeRect.maxY))
                context.move(to: CGPoint(x: loupeRect.minX, y: loupeRect.minY + offset))
                context.addLine(to: CGPoint(x: loupeRect.maxX, y: loupeRect.minY + offset))
                offset += step
            }
            context.strokePath()
        }

        context.restoreGState()

        drawCrosshair(in: context, center: center, loupeRect: loupeRect, precise: precise)
        drawRim(in: context, loupeRect: loupeRect, precise: precise)
        drawReadout(in: context, center: center, loupeRect: loupeRect, precise: precise)
    }

    /// The centre square is exactly one source pixel, so it grows with the zoom.
    /// Precise mode also thickens the stroke and extends the arms.
    private func drawCrosshair(in context: CGContext,
                               center: CGPoint,
                               loupeRect: CGRect,
                               precise: Bool) {
        let pixelSize = LoupeView.diameter / CGFloat(pixelsAcross)
        let square = CGRect(x: center.x - pixelSize / 2,
                            y: center.y - pixelSize / 2,
                            width: pixelSize,
                            height: pixelSize)

        let lineWidth: CGFloat = precise ? 2.5 : 1.5
        let armLength: CGFloat = precise ? 26 : 14

        context.saveGState()
        context.addPath(CGPath(ellipseIn: loupeRect, transform: nil))
        context.clip()

        // Draw dark then light so the crosshair reads on any colour beneath it.
        for (color, width) in [(NSColor.black.withAlphaComponent(0.55), lineWidth + 2),
                               (NSColor.white, lineWidth)] {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)

            context.stroke(square.insetBy(dx: -width / 2, dy: -width / 2))

            context.move(to: CGPoint(x: square.minX - armLength, y: center.y))
            context.addLine(to: CGPoint(x: square.minX - 2, y: center.y))
            context.move(to: CGPoint(x: square.maxX + 2, y: center.y))
            context.addLine(to: CGPoint(x: square.maxX + armLength, y: center.y))
            context.move(to: CGPoint(x: center.x, y: square.minY - armLength))
            context.addLine(to: CGPoint(x: center.x, y: square.minY - 2))
            context.move(to: CGPoint(x: center.x, y: square.maxY + 2))
            context.addLine(to: CGPoint(x: center.x, y: square.maxY + armLength))
            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawRim(in context: CGContext, loupeRect: CGRect, precise: Bool) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(precise ? 4 : 3)
        context.strokeEllipse(in: loupeRect.insetBy(dx: 1.5, dy: 1.5))

        context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: loupeRect.insetBy(dx: -0.5, dy: -0.5))
    }

    private func drawReadout(in context: CGContext,
                             center: CGPoint,
                             loupeRect: CGRect,
                             precise: Bool) {
        guard let color = centerColor else { return }
        let swatch = Swatch(color: color)

        var text = swatch.hex.uppercased()
        if precise { text += "   \(Int(zoom))×" }

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()

        let padding: CGFloat = 8
        var pill = CGRect(x: center.x - (textSize.width + padding * 2) / 2,
                          y: loupeRect.minY - textSize.height - padding * 2 - 8,
                          width: textSize.width + padding * 2,
                          height: textSize.height + padding)

        // Flip above the loupe if we'd fall off the bottom of the screen.
        if pill.minY < bounds.minY + 4 {
            pill.origin.y = loupeRect.maxY + 8
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
        context.addPath(CGPath(roundedRect: pill, cornerWidth: 7, cornerHeight: 7,
                               transform: nil))
        context.fillPath()

        NSGraphicsContext.current?.saveGraphicsState()
        string.draw(at: CGPoint(x: pill.minX + padding,
                                y: pill.minY + padding / 2))
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: Events

    override func mouseMoved(with event: NSEvent) {
        controller?.capture()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        controller?.commitCurrentColor()
    }

    override func flagsChanged(with event: NSEvent) {
        controller?.setPreciseMode(event.modifierFlags.contains(.control))
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / 8
            : event.scrollingDeltaY
        guard abs(delta) >= 0.5 else { return }
        controller?.adjustBaseZoom(by: delta > 0 ? 2 : -2)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Escape
            controller?.cancel()
        case 36, 49: // Return, Space
            controller?.commitCurrentColor()
        case 123: controller?.nudge(dx: -1, dy: 0)
        case 124: controller?.nudge(dx: 1, dy: 0)
        case 125: controller?.nudge(dx: 0, dy: -1)
        case 126: controller?.nudge(dx: 0, dy: 1)
        default: break
        }
        needsDisplay = true
    }
}
