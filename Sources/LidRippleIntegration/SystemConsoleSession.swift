import CoreGraphics
import Foundation
import IOKit

/// Both lock keys are OS implementation details, not a stable SDK contract.
/// Read through public APIs, accept only actual Booleans, and fail closed if
/// neither supplies evidence. Do not cache an unlocked result across sleep.
public enum SystemConsoleSession {
    public static func snapshot() -> (access: ConsoleSessionAccess, onConsole: Bool) {
        guard let before = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return (.unknown, false)
        }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        let consoleLocked: Bool?
        if root != 0 {
            defer { IOObjectRelease(root) }
            consoleLocked = boolean(IORegistryEntryCreateCFProperty(
                root, "IOConsoleLocked" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue())
        } else {
            consoleLocked = nil
        }
        guard let after = CGSessionCopyCurrentDictionary() as? [String: Any],
              let beforeID = before["kCGSSessionAuditIDKey"] as? NSNumber,
              let afterID = after["kCGSSessionAuditIDKey"] as? NSNumber,
              beforeID == afterID else { return (.unknown, false) }
        let onConsole = boolean(before["kCGSSessionOnConsoleKey"]) == true
            && boolean(after["kCGSSessionOnConsoleKey"]) == true
        let earlierLock = boolean(before["CGSSessionScreenIsLocked"])
        let laterLock = boolean(after["CGSSessionScreenIsLocked"])
        return (.resolve(
            onConsole: onConsole,
            screenLocked: earlierLock == true ? true : laterLock,
            consoleLocked: consoleLocked
        ), onConsole)
    }

    static func boolean(_ value: Any?) -> Bool? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
        else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
