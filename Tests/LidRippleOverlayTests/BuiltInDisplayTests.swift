import Testing
import AppKit
@testable import LidRippleOverlay

extension OverlayAppKitTests {
@Test func screenReturnsWithoutCrashingOnAnyHardware() {
    // No assertion on the result itself: a MacBook returns a screen, a desktop
    // Mac or a headless test runner returns nil. Both are valid per spec section 6.
    _ = BuiltInDisplay.screen()
}

@Test func screenIsOneOfTheConnectedScreensWhenPresent() {
    if let screen = BuiltInDisplay.screen() {
        #expect(NSScreen.screens.contains(screen))
        let displayID = BuiltInDisplay.displayID(for: screen)
        #expect(displayID != nil)
        if let displayID {
            #expect(CGDisplayIsBuiltin(displayID) != 0)
            #expect(BuiltInDisplay.displayID() == displayID)
        }
    }
}
}
