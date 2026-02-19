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
