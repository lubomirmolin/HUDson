import AppKit

enum MediaKey {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
}

struct MediaKeyPress {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    let modifiers: NSEvent.ModifierFlags
}

/// Catches the hardware media keys before the system sees them. Swallowing a key is what keeps
/// the stock HUD from ever appearing, so this needs Accessibility access.
final class MediaKeyTap {
    /// Return true to swallow the key, false to let macOS handle it.
    private let handler: (MediaKeyPress) -> Bool
    private var tap: CFMachPort?

    init(handler: @escaping (MediaKeyPress) -> Bool) {
        self.handler = handler
    }

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: systemDefined,
            callback: { _, type, event, refcon in
                let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        // Subtype 8 is NX_SUBTYPE_AUX_CONTROL_BUTTONS: the media/brightness keys.
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return pass }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0xFFFF
        let key: MediaKey
        switch keyCode {
        case 0: key = .volumeUp        // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown      // NX_KEYTYPE_SOUND_DOWN
        case 2: key = .brightnessUp    // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: key = .brightnessDown  // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 7: key = .mute            // NX_KEYTYPE_MUTE
        default: return pass
        }

        let press = MediaKeyPress(
            key: key,
            isDown: (keyFlags & 0xFF00) >> 8 == 0xA,
            isRepeat: keyFlags & 0x1 == 1,
            modifiers: nsEvent.modifierFlags
        )
        return handler(press) ? nil : pass
    }
}
