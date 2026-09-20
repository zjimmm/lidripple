/// Combines session ownership with explicit lock evidence. Neither an absent
/// dictionary key nor a distributed notification counts as unlocked evidence.
public enum ConsoleSessionAccess: Equatable, Sendable {
    case active
    case restricted
    case unknown

    public static func resolve(
        onConsole: Bool?,
        screenLocked: Bool?,
        consoleLocked: Bool? = nil
    ) -> ConsoleSessionAccess {
        if onConsole == false || screenLocked == true || consoleLocked == true {
            return .restricted
        }
        if onConsole == true, screenLocked == false || consoleLocked == false {
            return .active
        }
        return .unknown
    }
}
