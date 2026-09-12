import AppKit

/// The fold overlay's window, configured exactly per spec section 10.5: it must sit
/// above fullscreen apps and the menu bar, follow the user across Spaces without
/// itself being cycled through, never intercept a click, and never grow app-owned
/// chrome (title bar, shadow) that would look out of place drawn full-screen.
public final class OverlayWindow: NSWindow {
    public init(screen: NSScreen) {
        // NSWindow's `screen:` overload is a convenience initializer, so subclasses
        // must use this designated initializer. Supplying the target screen's frame
        // in global display coordinates places the window on that screen.
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // The presenter, not AppKit's window-closing machinery, owns this window's
        // lifetime — it is shown/hidden via orderFrontRegardless()/orderOut(), never
        // actually closed, so a stray close() call must not deallocate it.
        isReleasedWhenClosed = false
    }
}
