import Cocoa

/// Full-screen transparent window that dims everything except the capture frame.
class OverlayWindow: NSWindow {
    private(set) var overlayView: OverlayContentView!

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let contentView = OverlayContentView(frame: screen.frame)
        self.overlayView = contentView
        contentView.overlayWindow = self
        self.contentView = contentView

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.animationBehavior = .none
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
    }

    func show() { orderFront(nil) }
    func hide() { orderOut(nil) }
}
