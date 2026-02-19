import Cocoa
import CoreGraphics
import CGVirtualDisplayPrivate

@MainActor
class VirtualDisplayManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var displayID: CGDirectDisplayID = 0
    private(set) var currentWidth: Int = 0
    private(set) var currentHeight: Int = 0

    private var virtualDisplay: CGVirtualDisplay?
    private var renderWindow: NSWindow?
    private var renderView: NSView?

    /// Creates a virtual display with the given resolution.
    /// The virtual display appears as a sharable screen in meeting apps.
    func createDisplay(width: Int, height: Int) {
        tearDown()

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "ScreenSlice"
        descriptor.maxPixelsWide = UInt32(width)
        descriptor.maxPixelsHigh = UInt32(height)
        // Physical size in mm — set large enough to avoid HiDPI scaling issues
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.productID = 0x5C01
        descriptor.vendorID = 0x5C01
        descriptor.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: descriptor)

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: 60),
            CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: 30),
        ]
        display.apply(settings)

        self.virtualDisplay = display
        self.displayID = display.displayID
        self.currentWidth = width
        self.currentHeight = height
        self.isActive = true

        // Give macOS a moment to register the display, then create the render window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.createRenderWindow()
        }
    }

    /// Renders an IOSurface frame to the virtual display's render window.
    func renderFrame(_ surface: IOSurface) {
        renderView?.layer?.contents = surface
        if let window = renderWindow, window.alphaValue == 0 {
            window.alphaValue = 1
        }
    }

    /// Tears down the virtual display and render window.
    func tearDown() {
        renderWindow?.orderOut(nil)
        renderWindow = nil
        renderView = nil
        virtualDisplay = nil
        currentWidth = 0
        currentHeight = 0
        isActive = false
        displayID = 0
    }

    /// Updates the virtual display resolution, keeping the old window visible
    /// during the transition to prevent a flash.
    func updateResolution(width: Int, height: Int) {
        // Hold onto old window so it stays visible during the 1-second gap
        let oldWindow = renderWindow
        let oldDisplay = virtualDisplay

        // Detach without destroying
        renderWindow = nil
        renderView = nil
        virtualDisplay = nil

        // Create new display (skips tearDown since we already detached)
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "ScreenSlice"
        descriptor.maxPixelsWide = UInt32(width)
        descriptor.maxPixelsHigh = UInt32(height)
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 340)
        descriptor.productID = 0x5C01
        descriptor.vendorID = 0x5C01
        descriptor.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: 60),
            CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: 30),
        ]
        display.apply(settings)

        self.virtualDisplay = display
        self.displayID = display.displayID
        self.currentWidth = width
        self.currentHeight = height
        self.isActive = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.createRenderWindow()
            // Now safe to release old window and display
            oldWindow?.orderOut(nil)
            _ = oldDisplay
        }
    }

    // MARK: - Private

    private func createRenderWindow() {
        guard let display = virtualDisplay else { return }

        // Find the NSScreen for our virtual display
        guard let screen = NSScreen.screens.first(where: {
            let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return screenNumber == display.displayID
        }) else {
            print("ScreenSlice: Virtual display screen not found yet")
            return
        }

        // Create a borderless window covering the virtual display
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.setFrame(screen.frame, display: false)
        window.level = .normal
        window.backgroundColor = .black
        window.isOpaque = true
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces]
        window.alphaValue = 0 // Hidden until first frame is rendered

        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        window.orderFront(nil)

        self.renderWindow = window
        self.renderView = view
    }
}
