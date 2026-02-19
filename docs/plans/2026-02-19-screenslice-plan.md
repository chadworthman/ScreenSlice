# ScreenSlice Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that captures a resizable region of an ultrawide monitor and presents it as a virtual display for screen sharing.

**Architecture:** ScreenCaptureKit captures a user-defined rectangle on the ultrawide, frames are rendered to a borderless window positioned on a CGVirtualDisplay, and meeting apps share that virtual display. A dimming overlay with a movable/resizable cutout shows the user what's being shared.

**Tech Stack:** Swift, SwiftUI, AppKit, ScreenCaptureKit, CGVirtualDisplay (private API), IOSurface

---

### Task 1: Create Xcode Project

**Files:**
- Create: `ScreenSlice/ScreenSlice.xcodeproj` (via Xcode CLI)
- Create: `ScreenSlice/ScreenSliceApp.swift`
- Create: `ScreenSlice/Info.plist`
- Create: `ScreenSlice/ScreenSlice.entitlements`

**Step 1: Create the Xcode project using swift package**

Since we're building from CLI, create the project structure manually:

```bash
mkdir -p ScreenSlice/ScreenSlice
```

**Step 2: Create the Swift Package / Xcode project**

Create a `Package.swift` at the root:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenSlice",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenSlice",
            path: "ScreenSlice"
        ),
    ]
)
```

**Step 3: Create the app entry point**

Create `ScreenSlice/ScreenSliceApp.swift`:

```swift
import SwiftUI

@main
struct ScreenSliceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

**Step 4: Create the AppDelegate stub**

Create `ScreenSlice/AppDelegate.swift`:

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        print("ScreenSlice launched")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
```

**Step 5: Create Info.plist**

Create `ScreenSlice/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ScreenSlice</string>
    <key>CFBundleIdentifier</key>
    <string>com.screenslice.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>ScreenSlice needs screen recording access to capture the shared region of your display.</string>
</dict>
</plist>
```

**Step 6: Build and verify**

Run: `cd ScreenSlice && swift build`
Expected: Build succeeds, binary created.

Run: `.build/debug/ScreenSlice &` then check menu bar area, then `kill %1`
Expected: App launches as accessory (no dock icon), prints "ScreenSlice launched".

**Step 7: Commit**

```bash
git add ScreenSlice/ Package.swift
git commit -m "feat: scaffold ScreenSlice macOS app with menu bar presence"
```

---

### Task 2: Private API Bridging Header for CGVirtualDisplay

**Files:**
- Create: `ScreenSlice/CGVirtualDisplayPrivate.h`

**Step 1: Create the Objective-C bridging header**

Create `ScreenSlice/CGVirtualDisplayPrivate.h`:

```objc
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplayDescriptor;

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) CGFloat refreshRate;
@property(readonly, nonatomic) NSUInteger width;
@property(readonly, nonatomic) NSUInteger height;
- (instancetype)initWithWidth:(NSUInteger)arg1 height:(NSUInteger)arg2 refreshRate:(CGFloat)arg3;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) unsigned int hiDPI;
- (instancetype)init;
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
@property(readonly, nonatomic) NSString *name;
@property(readonly, nonatomic) unsigned int maxPixelsWide;
@property(readonly, nonatomic) unsigned int maxPixelsHigh;
@property(readonly, nonatomic) CGSize sizeInMillimeters;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)arg1;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)arg1;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay*);
- (instancetype)init;
- (void)setDispatchQueue:(dispatch_queue_t)arg1;
@end

NS_ASSUME_NONNULL_END
```

**Step 2: Configure Swift Package Manager to use the bridging header**

SPM doesn't natively support bridging headers. We need to restructure to use a C-interop target. Update `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenSlice",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CGVirtualDisplayPrivate",
            path: "ScreenSlice/CGVirtualDisplayPrivate",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "ScreenSlice",
            dependencies: ["CGVirtualDisplayPrivate"],
            path: "ScreenSlice/Sources"
        ),
    ]
)
```

Move source files accordingly:
```bash
mkdir -p ScreenSlice/CGVirtualDisplayPrivate
mkdir -p ScreenSlice/Sources
mv ScreenSlice/ScreenSliceApp.swift ScreenSlice/Sources/
mv ScreenSlice/AppDelegate.swift ScreenSlice/Sources/
mv ScreenSlice/Info.plist ScreenSlice/Sources/
mv ScreenSlice/CGVirtualDisplayPrivate.h ScreenSlice/CGVirtualDisplayPrivate/
```

Create `ScreenSlice/CGVirtualDisplayPrivate/module.modulemap`:

```
module CGVirtualDisplayPrivate {
    header "CGVirtualDisplayPrivate.h"
    export *
}
```

Create a placeholder C file so SPM recognizes the target:

Create `ScreenSlice/CGVirtualDisplayPrivate/placeholder.c`:

```c
// This file exists so SPM recognizes this as a C target.
```

**Step 3: Build and verify**

Run: `cd /path/to/project && swift build`
Expected: Build succeeds. The CGVirtualDisplay types are importable from Swift.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add CGVirtualDisplay private API bridging header"
```

---

### Task 3: Virtual Display Manager

**Files:**
- Create: `ScreenSlice/Sources/VirtualDisplayManager.swift`

**Step 1: Create the VirtualDisplayManager**

Create `ScreenSlice/Sources/VirtualDisplayManager.swift`:

```swift
import Cocoa
import CoreGraphics
import CGVirtualDisplayPrivate

@MainActor
class VirtualDisplayManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var displayID: CGDirectDisplayID = 0

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
        descriptor.productID = 0xSC01
        descriptor.vendorID = 0xSC01
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
        self.isActive = true

        // Give macOS a moment to register the display, then create the render window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.createRenderWindow()
        }
    }

    /// Renders an IOSurface frame to the virtual display's render window.
    func renderFrame(_ surface: IOSurface) {
        renderView?.layer?.contents = surface
    }

    /// Tears down the virtual display and render window.
    func tearDown() {
        renderWindow?.close()
        renderWindow = nil
        renderView = nil
        virtualDisplay = nil
        isActive = false
        displayID = 0
    }

    /// Updates the virtual display resolution (tears down and recreates).
    func updateResolution(width: Int, height: Int) {
        createDisplay(width: width, height: height)
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
            defer: false,
            screen: screen
        )
        window.level = .normal
        window.backgroundColor = .black
        window.isOpaque = true
        window.collectionBehavior = [.canJoinAllSpaces]

        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        window.orderFront(nil)

        self.renderWindow = window
        self.renderView = view
    }
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add ScreenSlice/Sources/VirtualDisplayManager.swift
git commit -m "feat: add VirtualDisplayManager for creating virtual display"
```

---

### Task 4: Screen Capture Manager

**Files:**
- Create: `ScreenSlice/Sources/ScreenCaptureManager.swift`

**Step 1: Create the ScreenCaptureManager**

Create `ScreenSlice/Sources/ScreenCaptureManager.swift`:

```swift
import Foundation
import ScreenCaptureKit
import CoreMedia

@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var isAudioEnabled = false

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var currentDisplay: SCDisplay?
    private var captureRect: CGRect = .zero
    private var currentFPS: Int = 30

    private let videoQueue = DispatchQueue(label: "com.screenslice.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.screenslice.audio", qos: .userInteractive)

    var onFrameReceived: ((IOSurface) -> Void)?

    override init() {
        super.init()
    }

    // MARK: - Public API

    /// Starts capturing the specified rectangle of the main display.
    func startCapture(rect: CGRect, fps: Int = 30, audio: Bool = false) async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }
        currentDisplay = display
        captureRect = rect
        currentFPS = fps
        isAudioEnabled = audio

        // Exclude our own app from capture
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let config = makeConfig(rect: rect, fps: fps, audio: audio)

        let output = StreamOutput { [weak self] surface in
            self?.onFrameReceived?(surface)
        }
        self.streamOutput = output

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoQueue)
        if audio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
        }

        try await stream.startCapture()
        self.stream = stream
        isCapturing = true
    }

    /// Stops the capture stream.
    func stopCapture() async throws {
        guard isCapturing, let stream = stream else { return }
        try await stream.stopCapture()
        self.stream = nil
        self.streamOutput = nil
        isCapturing = false
    }

    /// Updates the capture region without restarting.
    func updateCaptureRect(_ newRect: CGRect) async throws {
        guard isCapturing, let stream = stream else { return }
        captureRect = newRect
        let config = makeConfig(rect: newRect, fps: currentFPS, audio: isAudioEnabled)
        try await stream.updateConfiguration(config)
    }

    /// Toggles audio capture.
    func setAudio(_ enabled: Bool) async throws {
        guard isCapturing, let stream = stream else { return }
        isAudioEnabled = enabled
        let config = makeConfig(rect: captureRect, fps: currentFPS, audio: enabled)
        try await stream.updateConfiguration(config)
    }

    // MARK: - Private

    private func makeConfig(rect: CGRect, fps: Int, audio: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(rect.width)
        config.height = Int(rect.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 4
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.capturesAudio = audio
        if audio {
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }
        config.backgroundColor = .black
        return config
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            isCapturing = false
            print("ScreenSlice: Stream stopped with error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Stream Output

private class StreamOutput: NSObject, SCStreamOutput {
    let onSurface: (IOSurface) -> Void

    init(onSurface: @escaping (IOSurface) -> Void) {
        self.onSurface = onSurface
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachment = attachments.first,
              let statusRaw = attachment[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }

        guard let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            return
        }

        let ioSurface = unsafeBitCast(surface, to: IOSurface.self)
        onSurface(ioSurface)
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplayFound

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No display found."
        }
    }
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add ScreenSlice/Sources/ScreenCaptureManager.swift
git commit -m "feat: add ScreenCaptureManager for region capture"
```

---

### Task 5: Overlay Window with Dimming and Resizable Frame

**Files:**
- Create: `ScreenSlice/Sources/OverlayWindow.swift`
- Create: `ScreenSlice/Sources/OverlayContentView.swift`

**Step 1: Create the overlay window**

Create `ScreenSlice/Sources/OverlayWindow.swift`:

```swift
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
```

**Step 2: Create the overlay content view**

Create `ScreenSlice/Sources/OverlayContentView.swift`:

```swift
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

    /// Callback when the clear region changes (user drag/resize).
    var onRegionChanged: ((NSRect) -> Void)?

    private let handleSize: CGFloat = 8.0
    private let borderWidth: CGFloat = 2.0

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

        // Inside = move via border region
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
```

**Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add ScreenSlice/Sources/OverlayWindow.swift ScreenSlice/Sources/OverlayContentView.swift
git commit -m "feat: add overlay window with dimming and resizable frame"
```

---

### Task 6: Menu Bar Controller

**Files:**
- Create: `ScreenSlice/Sources/MenuBarController.swift`
- Modify: `ScreenSlice/Sources/AppDelegate.swift`

**Step 1: Create the menu bar controller**

Create `ScreenSlice/Sources/MenuBarController.swift`:

```swift
import Cocoa

/// Manages the menu bar status item and dropdown menu.
class MenuBarController {
    private var statusItem: NSStatusItem?
    private var startStopItem: NSMenuItem?
    private var audioItem: NSMenuItem?
    private var aspectRatioItems: [NSMenuItem] = []

    var onStartStop: (() -> Void)?
    var onAspectRatioChanged: ((CGFloat) -> Void)?
    var onAudioToggled: ((Bool) -> Void)?
    var onDimOpacityChanged: ((CGFloat) -> Void)?
    var onQuit: (() -> Void)?

    private var isSharing = false
    private var isAudioOn = false

    struct AspectPreset {
        let name: String
        let ratio: CGFloat
    }

    let presets: [AspectPreset] = [
        AspectPreset(name: "4:3", ratio: 4.0 / 3.0),
        AspectPreset(name: "16:9", ratio: 16.0 / 9.0),
        AspectPreset(name: "16:10", ratio: 16.0 / 10.0),
    ]

    private var selectedPresetIndex = 0

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "ScreenSlice")
        }

        let menu = NSMenu()

        // Start/Stop
        let startStop = NSMenuItem(title: "Start Sharing", action: #selector(toggleSharing), keyEquivalent: "s")
        startStop.target = self
        menu.addItem(startStop)
        self.startStopItem = startStop

        menu.addItem(NSMenuItem.separator())

        // Aspect ratio submenu
        let aspectMenu = NSMenu()
        for (index, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(selectAspectRatio(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == selectedPresetIndex ? .on : .off
            aspectMenu.addItem(item)
            aspectRatioItems.append(item)
        }
        let aspectItem = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        aspectItem.submenu = aspectMenu
        menu.addItem(aspectItem)

        // Audio toggle
        let audio = NSMenuItem(title: "Share Audio", action: #selector(toggleAudio), keyEquivalent: "a")
        audio.target = self
        audio.state = .off
        menu.addItem(audio)
        self.audioItem = audio

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit ScreenSlice", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    func updateSharingState(_ sharing: Bool) {
        isSharing = sharing
        startStopItem?.title = sharing ? "Stop Sharing" : "Start Sharing"
    }

    @objc private func toggleSharing() {
        onStartStop?()
    }

    @objc private func selectAspectRatio(_ sender: NSMenuItem) {
        selectedPresetIndex = sender.tag
        for (index, item) in aspectRatioItems.enumerated() {
            item.state = index == selectedPresetIndex ? .on : .off
        }
        onAspectRatioChanged?(presets[selectedPresetIndex].ratio)
    }

    @objc private func toggleAudio() {
        isAudioOn.toggle()
        audioItem?.state = isAudioOn ? .on : .off
        onAudioToggled?(isAudioOn)
    }

    @objc private func quitApp() {
        onQuit?()
    }
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add ScreenSlice/Sources/MenuBarController.swift
git commit -m "feat: add menu bar controller with aspect ratio and audio controls"
```

---

### Task 7: Wire Everything Together in AppDelegate

**Files:**
- Modify: `ScreenSlice/Sources/AppDelegate.swift`

**Step 1: Update AppDelegate to orchestrate all components**

Replace `ScreenSlice/Sources/AppDelegate.swift` with:

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarController()
    private let virtualDisplay = VirtualDisplayManager()
    private let captureManager = ScreenCaptureManager()
    private var overlayWindow: OverlayWindow?

    private var isSharing = false
    private var currentAspectRatio: CGFloat = 4.0 / 3.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar.setup()

        menuBar.onStartStop = { [weak self] in
            guard let self else { return }
            if isSharing {
                Task { await self.stopSharing() }
            } else {
                Task { await self.startSharing() }
            }
        }

        menuBar.onAspectRatioChanged = { [weak self] ratio in
            self?.changeAspectRatio(ratio)
        }

        menuBar.onAudioToggled = { [weak self] enabled in
            guard let self else { return }
            Task {
                try? await self.captureManager.setAudio(enabled)
            }
        }

        menuBar.onQuit = { [weak self] in
            Task {
                await self?.stopSharing()
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Sharing Lifecycle

    @MainActor
    private func startSharing() async {
        guard let screen = NSScreen.main else { return }

        // Calculate default frame: centered, aspect-ratio correct, ~60% of screen height
        let screenFrame = screen.frame
        let frameHeight = screenFrame.height * 0.6
        let frameWidth = frameHeight * currentAspectRatio
        let frameX = screenFrame.midX - frameWidth / 2
        let frameY = screenFrame.midY - frameHeight / 2
        let captureRegion = NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)

        // 1. Create overlay
        let overlay = OverlayWindow(screen: screen)
        overlay.overlayView.aspectRatio = currentAspectRatio
        overlay.overlayView.clearRegion = captureRegion
        overlay.show()
        self.overlayWindow = overlay

        // 2. Create virtual display matching capture region size
        virtualDisplay.createDisplay(width: Int(captureRegion.width), height: Int(captureRegion.height))

        // 3. Connect frame updates from overlay to capture manager
        overlay.overlayView.onRegionChanged = { [weak self] newRegion in
            guard let self else { return }
            Task {
                try? await self.captureManager.updateCaptureRect(newRegion)
                // Update virtual display resolution if size changed significantly
                self.virtualDisplay.updateResolution(
                    width: Int(newRegion.width),
                    height: Int(newRegion.height)
                )
            }
        }

        // 4. Connect capture output to virtual display
        captureManager.onFrameReceived = { [weak self] surface in
            Task { @MainActor in
                self?.virtualDisplay.renderFrame(surface)
            }
        }

        // 5. Start capture
        do {
            try await captureManager.startCapture(rect: captureRegion, fps: 30, audio: false)
            isSharing = true
            menuBar.updateSharingState(true)
        } catch {
            print("ScreenSlice: Failed to start capture: \(error)")
            overlay.hide()
            overlayWindow = nil
            virtualDisplay.tearDown()
        }
    }

    @MainActor
    private func stopSharing() async {
        try? await captureManager.stopCapture()
        overlayWindow?.hide()
        overlayWindow = nil
        virtualDisplay.tearDown()
        isSharing = false
        menuBar.updateSharingState(false)
    }

    private func changeAspectRatio(_ ratio: CGFloat) {
        currentAspectRatio = ratio
        overlayWindow?.overlayView.aspectRatio = ratio

        // Recalculate region with new aspect ratio, keeping center and height
        if let overlay = overlayWindow {
            var region = overlay.overlayView.clearRegion
            let centerX = region.midX
            let centerY = region.midY
            region.size.width = region.size.height * ratio
            region.origin.x = centerX - region.width / 2
            region.origin.y = centerY - region.height / 2
            overlay.overlayView.clearRegion = region
            overlay.overlayView.onRegionChanged?(region)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 3: Run the app**

Run: `.build/debug/ScreenSlice`
Expected:
- Menu bar icon appears (rectangle.dashed)
- Clicking "Start Sharing" shows the dimming overlay with a 4:3 frame
- Frame is draggable and resizable
- Virtual display appears in System Settings > Displays
- Clicking "Stop Sharing" removes overlay and virtual display

**Step 4: Commit**

```bash
git add ScreenSlice/Sources/AppDelegate.swift
git commit -m "feat: wire all components together — sharing lifecycle complete"
```

---

### Task 8: Build as .app Bundle

**Files:**
- Create: `scripts/build-app.sh`

**Step 1: Create the build script**

Create `scripts/build-app.sh`:

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="ScreenSlice"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "ScreenSlice/Sources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "App bundle created at: $APP_BUNDLE"
echo "To install: cp -r \"$APP_BUNDLE\" /Applications/"
```

**Step 2: Make it executable and test**

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

Expected: `.build/release/ScreenSlice.app` is created.

Run: `open .build/release/ScreenSlice.app`
Expected: App launches from the bundle, menu bar icon appears.

**Step 3: Commit**

```bash
git add scripts/build-app.sh
git commit -m "feat: add build script for .app bundle"
```

---

### Task 9: Testing and Polish

**Step 1: Manual test — full workflow**

1. Build and launch: `./scripts/build-app.sh && open .build/release/ScreenSlice.app`
2. Click menu bar icon → Start Sharing
3. Verify: dimming overlay appears with 4:3 frame
4. Drag the frame around — verify it moves smoothly
5. Resize using corner handles — verify aspect ratio locks
6. Open System Settings > Displays — verify "ScreenSlice" display appears
7. Open Zoom/Google Meet → Share Screen → verify "ScreenSlice" is listed
8. Share the ScreenSlice display — verify the frame region content appears
9. Move windows in/out of the frame on your ultrawide — verify they appear/disappear in the share
10. Change aspect ratio to 16:9 from menu — verify frame updates
11. Toggle audio from menu
12. Click Stop Sharing — verify overlay disappears, virtual display removed
13. Quit from menu

**Step 2: Fix any issues found during testing**

Address bugs found in step 1. Common issues to watch for:
- Frame not updating capture rect on drag (check onRegionChanged callback)
- Virtual display not appearing (check CGVirtualDisplay creation timing)
- Click-through not working (check hitTest and ignoresMouseEvents)
- Aspect ratio not enforced (check enforceAspectRatio logic)

**Step 3: Commit fixes**

```bash
git add -A
git commit -m "fix: address issues found during manual testing"
```

---

### Task 10: Final Cleanup

**Step 1: Review all files for dead code or debug prints**

Remove any `print()` statements that aren't useful for debugging in production.

**Step 2: Verify clean build**

```bash
swift build -c release 2>&1
```

Expected: No warnings, clean build.

**Step 3: Final commit**

```bash
git add -A
git commit -m "chore: clean up debug output and finalize v1.0"
```
