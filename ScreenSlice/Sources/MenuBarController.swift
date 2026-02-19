import Cocoa

/// Manages the menu bar status item and dropdown menu.
@MainActor
class MenuBarController {
    private var statusItem: NSStatusItem?
    private var startStopItem: NSMenuItem?
    private var audioItem: NSMenuItem?
    private var aspectRatioItems: [NSMenuItem] = []

    var onStartStop: (() -> Void)?
    var onAspectRatioChanged: ((CGFloat) -> Void)?
    var onAudioToggled: ((Bool) -> Void)?
    var onDimOpacityChanged: ((CGFloat) -> Void)?
    var onCheckPermissions: (() -> Void)?
    var onQuit: (() -> Void)?

    private var isSharing = false
    private var isAudioOn = false
    private var dimSlider: NSSlider?

    struct AspectPreset {
        let name: String
        let ratio: CGFloat
    }

    let presets: [AspectPreset] = [
        AspectPreset(name: "4:3", ratio: 4.0 / 3.0),
        AspectPreset(name: "16:9", ratio: 16.0 / 9.0),
        AspectPreset(name: "16:10", ratio: 16.0 / 10.0),
        AspectPreset(name: "3:4", ratio: 3.0 / 4.0),
        AspectPreset(name: "9:16", ratio: 9.0 / 16.0),
        AspectPreset(name: "10:16", ratio: 10.0 / 16.0),
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
        let landscapeHeader = NSMenuItem(title: "Landscape", action: nil, keyEquivalent: "")
        landscapeHeader.isEnabled = false
        aspectMenu.addItem(landscapeHeader)
        let verticalStart = 3 // index where vertical presets begin
        for (index, preset) in presets.enumerated() {
            if index == verticalStart {
                aspectMenu.addItem(NSMenuItem.separator())
                let portraitHeader = NSMenuItem(title: "Portrait", action: nil, keyEquivalent: "")
                portraitHeader.isEnabled = false
                aspectMenu.addItem(portraitHeader)
            }
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

        // Dim opacity slider
        let sliderContainer = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 46))
        let label = NSTextField(labelWithString: "Dim Effect")
        label.frame = NSRect(x: 14, y: 24, width: 172, height: 18)
        label.font = NSFont.menuFont(ofSize: 0)
        let slider = NSSlider(value: 0.35, minValue: 0.0, maxValue: 0.8, target: self, action: #selector(dimSliderChanged(_:)))
        slider.frame = NSRect(x: 22, y: 2, width: 164, height: 20)
        sliderContainer.addSubview(label)
        sliderContainer.addSubview(slider)
        self.dimSlider = slider
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderContainer
        menu.addItem(sliderItem)

        menu.addItem(NSMenuItem.separator())

        // Check Permissions
        let perms = NSMenuItem(title: "Check Permissions", action: #selector(checkPermissions), keyEquivalent: "p")
        perms.target = self
        menu.addItem(perms)

        menu.addItem(NSMenuItem.separator())

        // GitHub
        let github = NSMenuItem(title: "GitHub Repository", action: #selector(openGitHub), keyEquivalent: "")
        github.target = self
        menu.addItem(github)

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

    @objc private func dimSliderChanged(_ sender: NSSlider) {
        onDimOpacityChanged?(CGFloat(sender.doubleValue))
    }

    @objc private func checkPermissions() {
        onCheckPermissions?()
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/chadworthman/ScreenSlice") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        onQuit?()
    }
}
