/// Pure interpretation of the CoreGraphics session dictionary. The screen-lock
/// key is present on current macOS but is not declared in the public Swift SDK,
/// so absence remains explicit rather than being mistaken for "unlocked".
public enum ConsoleSessionAccess: Equatable, Sendable {
    case active
    case restricted
    case unknown

    public static func resolve(
        onConsole: Bool?,
        screenLocked: Bool?
    ) -> ConsoleSessionAccess {
        if onConsole == false || screenLocked == true { return .restricted }
        if onConsole == true, screenLocked == false { return .active }
        return .unknown
    }
}
