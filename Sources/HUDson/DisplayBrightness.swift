import AppKit

/// Display brightness through the private DisplayServices framework, the same one the system
/// brightness keys use. Covers the built-in panel and Apple displays; third-party monitors would
/// need DDC, which is out of scope.
enum DisplayBrightness {
    struct Target {
        let display: CGDirectDisplayID
        let screen: NSScreen
        var isBuiltIn: Bool { CGDisplayIsBuiltin(display) != 0 }
    }

    /// The display under the mouse if it supports brightness, otherwise the built-in one.
    static func target() -> Target? {
        let mouse = NSEvent.mouseLocation
        let candidates = NSScreen.screens.compactMap { screen -> Target? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let target = Target(display: number.uint32Value, screen: screen)
            return canChange(target.display) ? target : nil
        }
        return candidates.first { NSMouseInRect(mouse, $0.screen.frame, false) }
            ?? candidates.first { $0.isBuiltIn }
    }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(display, &value) == 0 ? value : nil
    }

    static func set(_ display: CGDirectDisplayID, _ value: Float) {
        _ = setBrightness?(display, min(max(value, 0), 1))
    }

    private static func canChange(_ display: CGDirectDisplayID) -> Bool {
        canChangeBrightness?(display) ?? false
    }

    private static let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let framework, let pointer = dlsym(framework, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool

    private static let getBrightness = symbol("DisplayServicesGetBrightness", as: GetFn.self)
    private static let setBrightness = symbol("DisplayServicesSetBrightness", as: SetFn.self)
    private static let canChangeBrightness = symbol("DisplayServicesCanChangeBrightness", as: CanFn.self)
}
