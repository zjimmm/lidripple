import Testing
import Foundation
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

@Test func registryEvidenceRecoversMissingSessionLockKey() {
    #expect(ConsoleSessionAccess.resolve(onConsole: true, screenLocked: nil,
                                       consoleLocked: false) == .active)
    for onConsole: Bool? in [true, false, nil] {
        for sessionLock: Bool? in [true, false, nil] {
            for registryLock: Bool? in [true, false, nil] {
                let result = ConsoleSessionAccess.resolve(onConsole: onConsole,
                    screenLocked: sessionLock, consoleLocked: registryLock)
                if onConsole == false || sessionLock == true || registryLock == true {
                    #expect(result == .restricted)
                } else if onConsole == true && (sessionLock == false || registryLock == false) {
                    #expect(result == .active)
                } else {
                    #expect(result == .unknown)
                }
            }
        }
    }
}

@Test func lockEvidenceRejectsNumbersStringsAndMissingValues() {
    #expect(SystemConsoleSession.boolean(nil) == nil)
    #expect(SystemConsoleSession.boolean("false") == nil)
    #expect(SystemConsoleSession.boolean(NSNumber(value: 0)) == nil)
    #expect(SystemConsoleSession.boolean(NSNumber(value: 1)) == nil)
    #expect(SystemConsoleSession.boolean(false) == false)
    #expect(SystemConsoleSession.boolean(true) == true)
}
