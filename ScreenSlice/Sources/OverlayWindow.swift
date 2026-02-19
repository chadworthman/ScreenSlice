import Cocoa

/// Full-screen transparent window that dims everything except the capture frame.
class OverlayWindow: NSWindow {
    let overlayView: OverlayContentView

    init(screen: NSScreen) {
        let contentView = OverlayContentView(frame: screen.frame)
        self.overlayView = contentView

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        contentView.overlayWindow = self
        self.contentView = contentView
    }

    func show() { orderFront(nil) }
    func hide() { orderOut(nil) }
}
