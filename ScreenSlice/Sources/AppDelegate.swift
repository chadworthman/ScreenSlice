import Cocoa

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

        menuBar.onQuit = { [weak self] in
            Task {
                await self?.stopSharing()
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Sharing Lifecycle

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
        // During drag: only update capture rect (lightweight)
        overlay.overlayView.onRegionChanged = { [weak self] newRegion in
            guard let self else { return }
            Task {
                try? await self.captureManager.updateCaptureRect(newRegion)
            }
        }

        // On mouse-up: update virtual display resolution (expensive, recreates display)
        overlay.overlayView.onRegionFinished = { [weak self] newRegion in
            guard let self else { return }
            self.virtualDisplay.updateResolution(
                width: Int(newRegion.width),
                height: Int(newRegion.height)
            )
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
            overlay.overlayView.onRegionFinished?(region)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
