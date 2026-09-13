import Testing
@testable import LidRippleIntegration

@Test func consoleSessionAccessRequiresPositiveUnlockedEvidence() {
    #expect(ConsoleSessionAccess.resolve(onConsole: true, screenLocked: false) == .active)
    #expect(ConsoleSessionAccess.resolve(onConsole: true, screenLocked: true) == .restricted)
    #expect(ConsoleSessionAccess.resolve(onConsole: false, screenLocked: false) == .restricted)
    #expect(ConsoleSessionAccess.resolve(onConsole: false, screenLocked: nil) == .restricted)
    #expect(ConsoleSessionAccess.resolve(onConsole: nil, screenLocked: true) == .restricted)
    #expect(ConsoleSessionAccess.resolve(onConsole: true, screenLocked: nil) == .unknown)
    #expect(ConsoleSessionAccess.resolve(onConsole: nil, screenLocked: false) == .unknown)
}
