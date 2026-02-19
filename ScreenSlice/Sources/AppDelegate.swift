import Cocoa
import ScreenCaptureKit

func ssLog(_ message: String) {
    NSLog("ScreenSlice: %@", message)
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
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

        menuBar.onDimOpacityChanged = { [weak self] opacity in
            self?.overlayWindow?.overlayView.dimOpacity = opacity
        }

        menuBar.onAudioToggled = { [weak self] enabled in
            guard let self else { return }
            Task {
                try? await self.captureManager.setAudio(enabled)
            }
        }

        menuBar.onCheckPermissions = {
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    let msg = """
                    Screen Recording: Authorized
                    Displays: \(content.displays.count)
                    Windows: \(content.windows.count)
                    Apps: \(content.applications.count)
                    """
                    ssLog(msg)
                    let alert = NSAlert()
                    alert.messageText = "Permissions OK"
                    alert.informativeText = msg
                    alert.runModal()
                } catch {
                    let msg = "Screen Recording: DENIED\nError: \(error)"
                    ssLog(msg)
                    let alert = NSAlert()
                    alert.messageText = "Permission Error"
                    alert.informativeText = msg
                    alert.runModal()
                }
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

    private func startSharing() async {
        ssLog("startSharing called")
        guard let screen = NSScreen.main else {
            ssLog("ERROR: No main screen found")
            return
        }

        // Calculate default frame: centered, aspect-ratio correct, ~60% of screen height
        let screenFrame = screen.frame
        let frameHeight = screenFrame.height * 0.6
        let frameWidth = frameHeight * currentAspectRatio
        let frameX = screenFrame.midX - frameWidth / 2
        let frameY = screenFrame.midY - frameHeight / 2
        let captureRegion = NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        ssLog("Capture region: \(captureRegion)")

        // 1. Create overlay
        ssLog("Creating overlay window...")
        let overlay = OverlayWindow(screen: screen)
        overlay.overlayView.aspectRatio = currentAspectRatio
        overlay.overlayView.clearRegion = captureRegion
        overlay.show()
        self.overlayWindow = overlay
        ssLog("Overlay shown")

        // 2. Create virtual display matching capture aspect ratio
        let (vw, vh) = displayDimensions(for: currentAspectRatio)
        ssLog("Creating virtual display \(vw)x\(vh)...")
        virtualDisplay.createDisplay(width: vw, height: vh)
        ssLog("Virtual display created, displayID=\(virtualDisplay.displayID)")

        // 3. Connect frame updates from overlay to capture manager
        // During drag: only update capture rect (lightweight)
        overlay.overlayView.onRegionChanged = { [weak self] newRegion in
            guard let self else { return }
            Task {
                try? await self.captureManager.updateCaptureRect(newRegion)
            }
        }

        // On mouse-up: recreate virtual display if aspect ratio changed
        overlay.overlayView.onRegionFinished = { [weak self] finalRegion in
            guard let self else { return }
            let regionRatio = finalRegion.width / finalRegion.height
            let (vw, vh) = self.displayDimensions(for: regionRatio)
            if vw != self.virtualDisplay.currentWidth || vh != self.virtualDisplay.currentHeight {
                ssLog("Region finished — updating virtual display to \(vw)x\(vh)")
                self.virtualDisplay.updateResolution(width: vw, height: vh)
            }
        }

        // 4. Connect capture output to virtual display
        captureManager.onFrameReceived = { [weak self] surface in
            Task { @MainActor in
                self?.virtualDisplay.renderFrame(surface)
            }
        }

        // 5. Start capture
        ssLog("Starting capture...")
        do {
            try await captureManager.startCapture(rect: captureRegion, fps: 30, audio: false)
            isSharing = true
            menuBar.updateSharingState(true)
            ssLog("Capture started successfully")
        } catch {
            ssLog("Failed to start capture: \(error)")
            ssLog("Error type: \(type(of: error))")
            overlay.hide()
            overlayWindow = nil
            virtualDisplay.tearDown()

            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "ScreenSlice needs Screen Recording permission to capture your display.\n\nGo to System Settings → Privacy & Security → Screen Recording, and enable ScreenSlice. You may need to quit and relaunch after granting access."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
    }

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

        // Recreate virtual display to match new aspect ratio
        if virtualDisplay.isActive {
            let (vw, vh) = displayDimensions(for: ratio)
            ssLog("Aspect ratio changed — updating virtual display to \(vw)x\(vh)")
            virtualDisplay.updateResolution(width: vw, height: vh)
        }
    }

    /// Computes virtual display dimensions for a given aspect ratio.
    /// For landscape (ratio >= 1): base height 1080, compute width.
    /// For portrait (ratio < 1): base width 1080, compute height.
    /// Dimensions are rounded to the nearest even number.
    private func displayDimensions(for ratio: CGFloat) -> (Int, Int) {
        if ratio >= 1.0 {
            let height = 1080
            let width = Int(round(CGFloat(height) * ratio / 2.0)) * 2
            return (width, height)
        } else {
            let width = 1080
            let height = Int(round(CGFloat(width) / ratio / 2.0)) * 2
            return (width, height)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
