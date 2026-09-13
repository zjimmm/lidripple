import Testing
import AppKit
@testable import LidRippleOverlay

/// NSWindow can be instantiated in a test host without a real display attached;
/// these assertions are all on static configuration, not live window-server
/// behavior (that part is manually verified per this plan's Task 6).
@Suite(.serialized)
@MainActor
struct OverlayAppKitTests {
@Test func isConfiguredAtTheShieldingLevel() {
    guard let screen = NSScreen.main else { return }  // CI/headless: nothing to assert
    let window = OverlayWindow(screen: screen)
    #expect(window.level.rawValue == Int(CGShieldingWindowLevel()))
}

@Test func hasTheExactCollectionBehaviorFromTheSpec() {
    guard let screen = NSScreen.main else { return }
    let window = OverlayWindow(screen: screen)
    let expected: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    #expect(window.collectionBehavior == expected)
}

@Test func ignoresMouseEventsAndHasNoChrome() {
    guard let screen = NSScreen.main else { return }
    let window = OverlayWindow(screen: screen)
    #expect(window.ignoresMouseEvents)
    #expect(!window.isOpaque)
    #expect(window.backgroundColor == .clear)
    #expect(!window.hasShadow)
    #expect(window.styleMask == [.borderless])
}

@Test func coversTheGivenScreensEntireFrame() {
    for screen in NSScreen.screens {
        let window = OverlayWindow(screen: screen)
        #expect(window.frame == screen.frame)
        #expect(window.screen == screen)
    }
}

@Test func isNotReleasedWhenClosed() {
    guard let screen = NSScreen.main else { return }
    let window = OverlayWindow(screen: screen)
    #expect(!window.isReleasedWhenClosed)
}
}
