import AppKit
import os
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let audio = AudioOutput()
    private let hud = HUDController(position: Settings.position)
    private lazy var keyTap = MediaKeyTap { [weak self] press in self?.handle(press) ?? false }
    private var statusItem: NSStatusItem?
    private var trustPoll: Timer?
    private let log = Logger(subsystem: "cz.lmolin.HUDson", category: "volume")
    private var lastLoggedLevel: (Float, Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if runPreviewIfRequested() { return }
        if !Settings.hideMenuBarIcon { installStatusItem() }
        audio.onExternalChange = { [weak self] in
            guard let self else { return }
            // CoreAudio fires several notifications per change; log each new level once.
            let level = (audio.volume, audio.isMuted)
            if lastLoggedLevel.map({ $0 != level }) ?? true {
                lastLoggedLevel = level
                log.notice("level now \(level.0) muted=\(level.1) device=\(self.audio.deviceName, privacy: .public)")
            }
            showVolume()
        }
        startKeyTap()
    }

    /// Opening the app again (Finder, Spotlight) brings a hidden menu bar icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Settings.hideMenuBarIcon = false
        installStatusItem()
        return false
    }

    // MARK: Keys

    private func startKeyTap() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt), keyTap.start() { return }

        // Wait for the user to flip the switch in System Settings.
        trustPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.keyTap.start() else { return }
            timer.invalidate()
            self.rebuildMenu()
        }
    }

    private func handle(_ press: MediaKeyPress) -> Bool {
        let modifiers = press.modifiers.intersection([.option, .shift, .control, .command])
        // Option + key opens the Sound / Displays settings; leave that to macOS.
        if modifiers == .option { return false }
        let fine = modifiers.contains([.option, .shift])
        log.notice("key \(String(describing: press.key), privacy: .public) down=\(press.isDown) repeat=\(press.isRepeat) mods=\(modifiers.rawValue)")

        switch press.key {
        case .volumeUp, .volumeDown, .mute:
            guard audio.canSetVolume else { return false }
            if press.isDown {
                if !(press.key == .mute && press.isRepeat) { adjustVolume(press.key, fine: fine) }
            } else if press.key != .mute {
                playFeedback(modifiers: modifiers)
            }
            return true

        case .brightnessUp, .brightnessDown:
            guard let target = DisplayBrightness.target() else { return false }
            if press.isDown { adjustBrightness(target, up: press.key == .brightnessUp, fine: fine) }
            return true
        }
    }

    private func adjustVolume(_ key: MediaKey, fine: Bool) {
        if key == .mute {
            audio.isMuted.toggle()
            showVolume()
            return
        }
        let step: Float = (fine ? 1 / 64 : 1 / 16) * (key == .volumeUp ? 1 : -1)
        let current = audio.volume
        let target = Self.stepped(current, by: step)
        if audio.isMuted { audio.isMuted = false }
        audio.volume = target
        log.notice("set \(current) -> \(target), reads back \(self.audio.volume)")
        showVolume(hitLimit: target == current)
    }

    private func adjustBrightness(_ target: DisplayBrightness.Target, up: Bool, fine: Bool) {
        guard let current = DisplayBrightness.get(target.display) else { return }
        let value = Self.stepped(current, by: (fine ? 1 / 64 : 1 / 16) * (up ? 1 : -1))
        DisplayBrightness.set(target.display, value)
        hud.show(value: Double(value),
                 symbol: Symbols.brightness(value, builtIn: target.isBuiltIn),
                 on: target.screen,
                 hitLimit: value == current)
    }

    private func showVolume(hitLimit: Bool = false) {
        let level = audio.volume
        let muted = audio.isMuted
        hud.show(value: muted ? 0 : Double(level),
                 symbol: Symbols.volume(level: level, muted: muted, kind: audio.kind),
                 on: Self.screenUnderMouse,
                 hitLimit: hitLimit)
    }

    /// Snaps to the step grid first, like the system does, so repeated presses don't drift.
    private static func stepped(_ value: Float, by step: Float) -> Float {
        let size = abs(step)
        return min(max((value / size).rounded() * size + step, 0), 1)
    }

    /// Mirrors the system: the feedback setting plays the pop, Shift inverts it.
    private func playFeedback(modifiers: NSEvent.ModifierFlags) {
        let invert = modifiers.contains(.shift) && !modifiers.contains(.option)
        guard Settings.volumeFeedback != invert else { return }
        NSSound(contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
                byReference: true)?.play()
    }

    private static var screenUnderMouse: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    // MARK: Menu

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusIcon
        statusItem = item
        rebuildMenu()
    }

    private static var statusIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            // Running outside the app bundle (swift run) has no resources.
            return NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "HUDson")
        }
        image.isTemplate = true
        image.accessibilityDescription = "HUDson"
        return image
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        if !keyTap.isRunning {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let positions = NSMenu()
        for position in HUDPosition.allCases {
            let entry = item(position.title, #selector(pickPosition(_:)))
            entry.representedObject = position.rawValue
            entry.state = position == hud.position ? .on : .off
            positions.addItem(entry)
        }
        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        positionItem.submenu = positions
        menu.addItem(positionItem)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Hide Menu Bar Icon", #selector(hideMenuBarIcon)))
        menu.addItem(.separator())
        menu.addItem(item("Quit HUDson", #selector(NSApplication.terminate(_:)), target: NSApp))

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target ?? self
        return item
    }

    @objc private func pickPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = HUDPosition(rawValue: raw) else { return }
        Settings.position = position
        hud.position = position
        rebuildMenu()
        showVolume()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
        rebuildMenu()
    }

    @objc private func hideMenuBarIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = "Open HUDson again from Finder or Spotlight to bring it back."
        alert.addButton(withTitle: "Hide")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        Settings.hideMenuBarIcon = true
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Preview

    /// `--preview <volume|mute|brightness> <0…1> [topRight|rightEdge|bottomCenter]` pins a HUD
    /// on screen without touching any keys or levels. Handy for screenshots.
    private func runPreviewIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--preview"), args.count > index + 2 else { return false }
        let value = Double(args[index + 2]) ?? 0.5
        if args.count > index + 3, let position = HUDPosition(rawValue: args[index + 3]) {
            hud.position = position
        }
        let symbol = switch args[index + 1] {
        case "brightness": Symbols.brightness(Float(value), builtIn: true)
        case "mute": Symbols.volume(level: 0, muted: true, kind: .speakers)
        default: Symbols.volume(level: Float(value), muted: false, kind: audio.kind)
        }
        hud.persistent = true
        hud.show(value: value, symbol: symbol, on: NSScreen.main)
        return true
    }
}
