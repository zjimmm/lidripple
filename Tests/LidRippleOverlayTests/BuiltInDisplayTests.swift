import Testing
import AppKit
@testable import LidRippleOverlay

@Test func screenReturnsWithoutCrashingOnAnyHardware() {
    // No assertion on the result itself: a MacBook returns a screen, a desktop
    // Mac or a headless test runner returns nil. Both are valid per spec section 6.
    _ = BuiltInDisplay.screen()
}

@Test func screenIsOneOfTheConnectedScreensWhenPresent() {
    if let screen = BuiltInDisplay.screen() {
        #expect(NSScreen.screens.contains(screen))
    }
}
