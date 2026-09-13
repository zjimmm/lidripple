#!/usr/bin/env swift

// Opt-in S7 diagnostic. This process never delays, cancels, or requests sleep;
// it only observes public workspace notifications and a best-effort IORegistry
// clamshell property. The registry property is diagnostic, not a product API.
import AppKit
import CoreGraphics
import Foundation
import IOKit

private func clamshellClosed() -> Bool? {
    guard let match = IOServiceMatching("IOPMrootDomain") else { return nil }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard let property = IORegistryEntryCreateCFProperty(
        service,
        "AppleClamshellState" as CFString,
        kCFAllocatorDefault,
        0
    ) else { return nil }
    return property.takeRetainedValue() as? Bool
}

private func sessionLabel() -> String {
    guard let values = CGSessionCopyCurrentDictionary() as? [String: Any] else {
        return "unknown"
    }
    let onConsole = values["kCGSSessionOnConsoleKey"] as? Bool
    let locked = values["CGSSessionScreenIsLocked"] as? Bool
    return "console=\(onConsole.map(String.init(describing:)) ?? "unknown"),locked=\(locked.map(String.init(describing:)) ?? "unknown")"
}

private func log(_ event: String) {
    let lid = clamshellClosed().map { $0 ? "closed" : "open" } ?? "unknown"
    print(String(
        format: "uptime=%.6f wall=%@ event=%@ lid=%@ %@",
        ProcessInfo.processInfo.systemUptime,
        Date().ISO8601Format(),
        event,
        lid,
        sessionLabel()
    ))
    fflush(stdout)
}

let workspace = NSWorkspace.shared.notificationCenter
let names: [(Notification.Name, String)] = [
    (NSWorkspace.willSleepNotification, "workspace.willSleep"),
    (NSWorkspace.didWakeNotification, "workspace.didWake"),
    (NSWorkspace.screensDidSleepNotification, "screens.didSleep"),
    (NSWorkspace.screensDidWakeNotification, "screens.didWake"),
    (NSWorkspace.sessionDidResignActiveNotification, "session.resigned"),
    (NSWorkspace.sessionDidBecomeActiveNotification, "session.active"),
]
var observers: [NSObjectProtocol] = names.map { name, label in
    workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
        log(label)
    }
}
observers.append(DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name("com.apple.screenIsLocked"),
    object: nil,
    queue: .main
) { _ in log("screen.locked") })
observers.append(DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name("com.apple.screenIsUnlocked"),
    object: nil,
    queue: .main
) { _ in log("screen.unlocked") })

var previousLid = clamshellClosed()
log("probe.started")
let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
    let current = clamshellClosed()
    guard current != previousLid else { return }
    previousLid = current
    log(current == true ? "registry.lidClosed" : "registry.lidOpen")
}
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
