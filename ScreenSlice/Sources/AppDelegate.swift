import Cocoa
import ScreenCaptureKit

private let logFile: URL = {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ScreenSlice.log")
    // Clear log on launch
    try? "".write(to: url, atomically: true, encoding: .utf8)
    return url
}()

func ssLog(_ message: String) {
    let line = "\(Date()): \(message)\n"
    NSLog("ScreenSlice: %@", message)
    if let data = line.data(using: .utf8),
       let handle = try? FileHandle(forWritingTo: logFile) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }
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

        // 2. Create virtual display at fixed 1920x1080 — created once, never resized
        ssLog("Creating virtual display 1920x1080...")
        virtualDisplay.createDisplay(width: 1920, height: 1080)
        ssLog("Virtual display created, displayID=\(virtualDisplay.displayID)")

        // 3. Connect frame updates from overlay to capture manager
        // During drag: only update capture rect (lightweight)
        overlay.overlayView.onRegionChanged = { [weak self] newRegion in
            guard let self else { return }
            Task {
                try? await self.captureManager.updateCaptureRect(newRegion)
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
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
