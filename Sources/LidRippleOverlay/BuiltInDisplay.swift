import AppKit
import CoreGraphics

/// Locates the Mac's built-in display, if it has one.
///
/// Spec FR-13: the fold plays only on the built-in panel. Desktop Macs, and any
/// external-only configuration, correctly return nil rather than guessing.
public enum BuiltInDisplay {
    public static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard
            let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
        else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    public static func displayID() -> CGDirectDisplayID? {
        screen().flatMap(displayID(for:))
    }

    public static func screen() -> NSScreen? {
        for screen in NSScreen.screens {
            guard let displayID = displayID(for: screen) else { continue }
            if CGDisplayIsBuiltin(displayID) != 0 {
                return screen
            }
        }
        return nil
    }
}
