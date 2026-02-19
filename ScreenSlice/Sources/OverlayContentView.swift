import Cocoa

/// Renders the dimming overlay with a transparent cutout and handles
/// drag/resize interactions on the frame border.
class OverlayContentView: NSView {
    weak var overlayWindow: OverlayWindow?

    /// The region that stays clear (not dimmed). This is the capture area.
    var clearRegion: NSRect = .zero {
        didSet { needsDisplay = true }
    }

    /// Dimming opacity (0.0 - 1.0). Default 0.35.
    var dimOpacity: CGFloat = 0.35 {
        didSet { needsDisplay = true }
    }

    /// Locked aspect ratio (width/height). Nil = free resize.
    var aspectRatio: CGFloat? = 4.0 / 3.0

    /// Callback when the clear region changes (user drag/resize). Fires during drag.
    var onRegionChanged: ((NSRect) -> Void)?

    /// Callback when the user finishes a drag/resize (mouse-up). Use for expensive updates.
    var onRegionFinished: ((NSRect) -> Void)?

    private let handleSize: CGFloat = 8.0
    private let borderWidth: CGFloat = 2.0
    private let dragBarWidth: CGFloat = 60.0
    private let dragBarHeight: CGFloat = 8.0
    private let dragBarOffset: CGFloat = 16.0 // distance from top edge into the clear region

    private enum Interaction {
        case none, move
        case resizeTopLeft, resizeTopRight, resizeBottomLeft, resizeBottomRight
        case resizeTop, resizeBottom, resizeLeft, resizeRight
    }

    private var currentInteraction: Interaction = .none
    private var mouseDownPoint: NSPoint = .zero
    private var originalRegion: NSRect = .zero
    private var trackingArea: NSTrackingArea?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupTracking() {
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        setupTracking()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard clearRegion.width > 0, clearRegion.height > 0 else {
            // No region defined yet — dim everything
            NSColor.black.withAlphaComponent(dimOpacity).setFill()
            bounds.fill()
            return
        }

        // Even-odd fill: dim everywhere except the clear region
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: clearRegion))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        path.fill()

        // Border around clear region
        let borderPath = NSBezierPath(rect: clearRegion)
        borderPath.lineWidth = borderWidth
        NSColor.white.withAlphaComponent(0.8).setStroke()
        borderPath.stroke()

        // Resize handles
        for rect in handleRects() {
            let handlePath = NSBezierPath(ovalIn: rect)
            NSColor.white.setFill()
            handlePath.fill()
        }

        // Drag handle bars (centered pills at top and bottom of clear region)
        for barRect in [topDragBarRect(), bottomDragBarRect()] {
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: dragBarHeight / 2, yRadius: dragBarHeight / 2)
            NSColor.black.withAlphaComponent(0.5).setStroke()
            barPath.lineWidth = 1.5
            barPath.stroke()
            NSColor.white.withAlphaComponent(0.9).setFill()
            barPath.fill()
        }
    }

    // MARK: - Handle Geometry

    private func handleRects() -> [NSRect] {
        let r = clearRegion
        let hs = handleSize
        let half = hs / 2.0
        return [
            NSRect(x: r.minX - half, y: r.maxY - half, width: hs, height: hs),
            NSRect(x: r.maxX - half, y: r.maxY - half, width: hs, height: hs),
            NSRect(x: r.minX - half, y: r.minY - half, width: hs, height: hs),
            NSRect(x: r.maxX - half, y: r.minY - half, width: hs, height: hs),
            NSRect(x: r.midX - half, y: r.maxY - half, width: hs, height: hs),
            NSRect(x: r.midX - half, y: r.minY - half, width: hs, height: hs),
            NSRect(x: r.minX - half, y: r.midY - half, width: hs, height: hs),
            NSRect(x: r.maxX - half, y: r.midY - half, width: hs, height: hs),
        ]
    }

    private func topDragBarRect() -> NSRect {
        let r = clearRegion
        return NSRect(
            x: r.midX - dragBarWidth / 2,
            y: r.maxY - dragBarOffset - dragBarHeight / 2,
            width: dragBarWidth,
            height: dragBarHeight
        )
    }

    private func bottomDragBarRect() -> NSRect {
        let r = clearRegion
        return NSRect(
            x: r.midX - dragBarWidth / 2,
            y: r.minY + dragBarOffset - dragBarHeight / 2,
            width: dragBarWidth,
            height: dragBarHeight
        )
    }

    private func interactionAt(_ point: NSPoint) -> Interaction {
        let tol: CGFloat = 12.0
        let r = clearRegion

        // Corner checks (priority)
        if dist(point, NSPoint(x: r.minX, y: r.maxY)) < tol { return .resizeTopLeft }
        if dist(point, NSPoint(x: r.maxX, y: r.maxY)) < tol { return .resizeTopRight }
        if dist(point, NSPoint(x: r.minX, y: r.minY)) < tol { return .resizeBottomLeft }
        if dist(point, NSPoint(x: r.maxX, y: r.minY)) < tol { return .resizeBottomRight }

        // Edge checks
        if abs(point.y - r.maxY) < tol && point.x > r.minX && point.x < r.maxX { return .resizeTop }
        if abs(point.y - r.minY) < tol && point.x > r.minX && point.x < r.maxX { return .resizeBottom }
        if abs(point.x - r.minX) < tol && point.y > r.minY && point.y < r.maxY { return .resizeLeft }
        if abs(point.x - r.maxX) < tol && point.y > r.minY && point.y < r.maxY { return .resizeRight }

        // Drag bars (centered pills at top and bottom) — move handles
        let topBar = topDragBarRect().insetBy(dx: -6, dy: -6)
        if topBar.contains(point) { return .move }
        let bottomBar = bottomDragBarRect().insetBy(dx: -6, dy: -6)
        if bottomBar.contains(point) { return .move }

        // Border region — also move
        let inner = r.insetBy(dx: tol, dy: tol)
        if r.contains(point) && !inner.contains(point) { return .move }

        return .none
    }

    private func dist(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        currentInteraction = interactionAt(p)
        mouseDownPoint = p
        originalRegion = clearRegion
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - mouseDownPoint.x
        let dy = p.y - mouseDownPoint.y
        var r = originalRegion

        switch currentInteraction {
        case .move:
            r.origin.x += dx
            r.origin.y += dy
        case .resizeTopLeft:
            r.origin.x += dx
            r.size.width -= dx
            r.size.height += dy
        case .resizeTopRight:
            r.size.width += dx
            r.size.height += dy
        case .resizeBottomLeft:
            r.origin.x += dx
            r.origin.y += dy
            r.size.width -= dx
            r.size.height -= dy
        case .resizeBottomRight:
            r.size.width += dx
            r.origin.y += dy
            r.size.height -= dy
        case .resizeTop:
            r.size.height += dy
        case .resizeBottom:
            r.origin.y += dy
            r.size.height -= dy
        case .resizeLeft:
            r.origin.x += dx
            r.size.width -= dx
        case .resizeRight:
            r.size.width += dx
        case .none:
            return
        }

        // Enforce aspect ratio on resize (not move)
        if let ratio = aspectRatio, currentInteraction != .move {
            r = enforceAspectRatio(r, ratio: ratio, interaction: currentInteraction)
        }

        // Enforce minimum size
        if r.width >= 200 && r.height >= 150 {
            clearRegion = r
            onRegionChanged?(r)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if currentInteraction != .none {
            onRegionFinished?(clearRegion)
        }
        currentInteraction = .none
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let interaction = interactionAt(p)

        switch interaction {
        case .move: NSCursor.openHand.set()
        case .resizeTop, .resizeBottom: NSCursor.resizeUpDown.set()
        case .resizeLeft, .resizeRight: NSCursor.resizeLeftRight.set()
        case .resizeTopLeft, .resizeBottomRight,
             .resizeTopRight, .resizeBottomLeft: NSCursor.crosshair.set()
        case .none: NSCursor.arrow.set()
        }

        // Pass through mouse events when not over interactive region
        overlayWindow?.ignoresMouseEvents = (interaction == .none)
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return interactionAt(p) != .none ? self : nil
    }

    // MARK: - Aspect Ratio

    private func enforceAspectRatio(_ rect: NSRect, ratio: CGFloat, interaction: Interaction) -> NSRect {
        var r = rect
        switch interaction {
        case .resizeLeft, .resizeRight:
            r.size.height = r.size.width / ratio
        default:
            r.size.width = r.size.height * ratio
        }
        return r
    }
}
