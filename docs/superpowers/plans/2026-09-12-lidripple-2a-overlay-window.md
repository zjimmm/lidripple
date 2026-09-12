# lidripple Plan 2a: Overlay Window and App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the minimal runnable app shell that hosts the fold overlay — a borderless window at the shielding level, positioned on the built-in display, driven live by the real lid sensor through the already-built `FoldDriver` — with no Metal and no screen capture yet, so it needs zero permissions and can be fully exercised today.

**Architecture:** Two new Swift package targets. `LidRippleOverlay` is a testable AppKit library holding `BuiltInDisplay` (finds the built-in screen), `OverlayWindow` (an `NSWindow` configured exactly to spec, whose configuration is asserted by unit test), `FoldPlaceholderView` (a stand-in for Plan 2c's Metal-rendered view — a plain view whose opacity tracks `FoldState.progress`), and `OverlayPresenter` (owns the window's show/hide lifecycle). `LidRippleApp` is a thin executable — `AppDelegate` wires `HIDAngleSource` → `FoldDriver` → `OverlayPresenter`, sets `NSApp.activationPolicy = .accessory` (the `LSUIElement` effect without needing an app bundle), and observes sleep/wake/lock/unlock. Window configuration is unit-tested; live window-server behavior (does it actually show at the right place when the lid closes) is manually verified, the same way Task 2 handled sensor hardware.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, `CGShieldingWindowLevel`. Depends on the `LidRippleCore`/`LidRippleSensor` targets already on `main` from the M0-M1 plan. No Metal, no ScreenCaptureKit, no TCC permissions — those arrive in Plans 2b/2c.

**Spec:** `docs/superpowers/specs/2026-09-12-lidripple-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Platform floor: macOS 14.0**, `swift-tools-version: 6.0` — unchanged from M0-M1.
- **Zero third-party dependencies.**
- **No network access anywhere.**
- **No screen capture, no Metal, no TCC permission prompt in this plan.** That is the
  entire reason this milestone is split out: it must be fully exercisable with zero
  permission dialogs. If a task's implementation seems to need `ScreenCaptureKit` or
  `Metal`, stop — that work belongs to Plan 2b or 2c, not here.
- **`LidRippleCore` stays untouched and import-clean.** This plan consumes `FoldDriver`,
  `FoldState`, `FoldPhase`, `AngleSample` from M0-M1 exactly as they exist on `main` —
  do not modify `LidRippleCore`, `LidRippleSensor`, or `LidRippleTrace` in this plan.
- **`LidRippleOverlay` imports only `Foundation`, `AppKit`, `CoreGraphics`, and
  `LidRippleCore`.** No `LidRippleSensor` import — the overlay library must not know
  about the sensor; that wiring belongs to the app target.
- **Commit style:** conventional commits. Every commit message ends with:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq
  ```
- **Build and test from repo root:** `swift build`, `swift test`.

## Requirement traceability

| Spec | Requirement | Task |
|---|---|---|
| FR-13 | Fold plays only on the built-in display | 1 (`BuiltInDisplay`) |
| §10.5 | Window sits above fullscreen apps and the menu bar: `CGShieldingWindowLevel()` with `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`, `ignoresMouseEvents` | 2 (`OverlayWindow`) |
| FR-1 | Nothing drawn while idle/armed | 3 (`OverlayPresenter.update`) |
| §10.1 | `willSleepNotification` is a hard jump to `sealed` | 5 (`AppDelegate.willSleep`) |
| §7.3 / FR-10 | Scripted unfold triggers on `com.apple.screenIsUnlocked` | 5 (`AppDelegate.screenDidUnlock`) |

**Deliberately NOT in scope here, though related:** FR-15/FR-16 (the full menu bar —
enable/disable, intensity slider, launch-at-login, permission state, debug scrubber) are
M5 work per the M0-M1 plan's own traceability table. Task 4 adds only a bare "Quit" menu
item — the minimum needed to have a running, quittable app process at all. Do not build
any more menu UI than that; expanding it now would duplicate M5's job. Likewise
`AppCoordinator` in the spec's architecture table names permission onboarding and the
debug scrubber as its responsibilities — `AppDelegate` in this plan is a deliberately
reduced seed of that unit, not the full thing.

---

## File Structure

| File | Responsibility |
|---|---|
| `Package.swift` | Modified: add `LidRippleOverlay` library target and `LidRippleApp` executable target |
| `Sources/LidRippleOverlay/BuiltInDisplay.swift` | Finds the built-in `NSScreen`, or nil on unsupported hardware |
| `Sources/LidRippleOverlay/OverlayWindow.swift` | `NSWindow` subclass configured per spec §10.5 |
| `Sources/LidRippleOverlay/FoldPlaceholderView.swift` | Stand-in content view; opacity tracks progress. Plan 2c replaces this with the Metal view |
| `Sources/LidRippleOverlay/OverlayPresenter.swift` | Owns the window; `init?()`, `update(_:)` |
| `Sources/LidRippleApp/AppDelegate.swift` | Wires sensor → driver → overlay; sleep/wake/lock/unlock observers |
| `Sources/LidRippleApp/main.swift` | Entry point |
| `Tests/LidRippleOverlayTests/BuiltInDisplayTests.swift` | Presence-check pattern, hardware-independent |
| `Tests/LidRippleOverlayTests/OverlayWindowTests.swift` | Asserts window configuration (level, collectionBehavior, etc.) |
| `Tests/LidRippleOverlayTests/FoldPlaceholderViewTests.swift` | Asserts `progress` drives `needsDisplay` |

---

## Task 1: BuiltInDisplay

**Files:**
- Create: `Sources/LidRippleOverlay/BuiltInDisplay.swift`
- Test: `Tests/LidRippleOverlayTests/BuiltInDisplayTests.swift`

**Interfaces:**
- Consumes: nothing (AppKit/CoreGraphics only).
- Produces: `enum BuiltInDisplay { static func screen() -> NSScreen? }`.

- [ ] **Step 1: Modify `Package.swift` to add the new targets**

Read the current `Package.swift` first (it has 3 libraries, 1 executable, 2 test targets
from M0-M1). Add, without removing anything existing:

```swift
        .library(name: "LidRippleOverlay", targets: ["LidRippleOverlay"]),
```
to `products`, and:
```swift
        .target(name: "LidRippleOverlay", dependencies: ["LidRippleCore"]),
        .executableTarget(
            name: "LidRippleApp",
            dependencies: ["LidRippleCore", "LidRippleSensor", "LidRippleOverlay"]
        ),
        .testTarget(name: "LidRippleOverlayTests", dependencies: ["LidRippleOverlay"]),
```
to `targets`. Leave the existing `LidRippleCore`/`LidRippleSensor`/`LidRippleTrace`/
`lidripple-trace`/test targets exactly as they are.

- [ ] **Step 2: Write the failing test**

Create `Tests/LidRippleOverlayTests/BuiltInDisplayTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter BuiltInDisplayTests`
Expected: FAIL — `cannot find 'BuiltInDisplay' in scope` (also confirms the new package
targets from Step 1 at least parse; a full `swift build` may still fail until Step 4's
file exists, that's expected).

- [ ] **Step 4: Write the implementation**

Create `Sources/LidRippleOverlay/BuiltInDisplay.swift`:

```swift
import AppKit
import CoreGraphics

/// Locates the Mac's built-in display, if it has one.
///
/// Spec FR-13: the fold plays only on the built-in panel. Desktop Macs, and any
/// external-only configuration, correctly return nil rather than guessing.
public enum BuiltInDisplay {
    public static func screen() -> NSScreen? {
        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            if CGDisplayIsBuiltin(displayID) != 0 {
                return screen
            }
        }
        return nil
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter BuiltInDisplayTests`
Expected: PASS, 2 tests.

Also run: `swift build`
Expected: builds with no errors (this compiles all four targets for the first time,
including the new empty-so-far `LidRippleApp` — see Step 6).

- [ ] **Step 6: Add a placeholder `main.swift` so the executable target builds**

Create `Sources/LidRippleApp/main.swift`:

```swift
// Filled in by Task 4.
print("lidripple-app: not implemented yet")
```

- [ ] **Step 7: Run the tests and build once more to confirm the whole package is green**

Run: `swift test` (full suite — should be 71 existing + 2 new = 73) and `swift build`.
Expected: both clean.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/LidRippleOverlay/BuiltInDisplay.swift Sources/LidRippleApp/main.swift Tests/LidRippleOverlayTests/BuiltInDisplayTests.swift
git commit -m "feat: add LidRippleOverlay/LidRippleApp targets and BuiltInDisplay

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 2: OverlayWindow

**Files:**
- Create: `Sources/LidRippleOverlay/OverlayWindow.swift`
- Test: `Tests/LidRippleOverlayTests/OverlayWindowTests.swift`

**Interfaces:**
- Consumes: `BuiltInDisplay` is not used directly here — this task takes an `NSScreen`
  as a parameter so it stays testable against any screen, including one synthesized in a
  test environment.
- Produces: `final class OverlayWindow: NSWindow { init(screen: NSScreen) }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleOverlayTests/OverlayWindowTests.swift`:

```swift
import Testing
import AppKit
@testable import LidRippleOverlay

/// NSWindow can be instantiated in a test host without a real display attached;
/// these assertions are all on static configuration, not live window-server
/// behavior (that part is manually verified per this plan's Task 6).
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
    guard let screen = NSScreen.main else { return }
    let window = OverlayWindow(screen: screen)
    #expect(window.frame == screen.frame)
}

@Test func isNotReleasedWhenClosed() {
    guard let screen = NSScreen.main else { return }
    let window = OverlayWindow(screen: screen)
    #expect(!window.isReleasedWhenClosed)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter OverlayWindowTests`
Expected: FAIL — `cannot find 'OverlayWindow' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/LidRippleOverlay/OverlayWindow.swift`:

```swift
import AppKit

/// The fold overlay's window, configured exactly per spec section 10.5: it must sit
/// above fullscreen apps and the menu bar, follow the user across Spaces without
/// itself being cycled through, never intercept a click, and never grow app-owned
/// chrome (title bar, shadow) that would look out of place drawn full-screen.
public final class OverlayWindow: NSWindow {
    public init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter OverlayWindowTests`
Expected: PASS, 5 tests (fewer if run in a headless environment with no `NSScreen.main`
— each test guards for that and returns early rather than failing).

- [ ] **Step 5: Commit**

```bash
git add Sources/LidRippleOverlay/OverlayWindow.swift Tests/LidRippleOverlayTests/OverlayWindowTests.swift
git commit -m "feat: add OverlayWindow configured per spec section 10.5

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 3: FoldPlaceholderView and OverlayPresenter

**Files:**
- Create: `Sources/LidRippleOverlay/FoldPlaceholderView.swift`
- Create: `Sources/LidRippleOverlay/OverlayPresenter.swift`
- Test: `Tests/LidRippleOverlayTests/FoldPlaceholderViewTests.swift`
- Test: `Tests/LidRippleOverlayTests/OverlayPresenterTests.swift`

**Interfaces:**
- Consumes: `OverlayWindow` (Task 2), `BuiltInDisplay` (Task 1), `FoldState`/`FoldPhase`
  from `LidRippleCore` (already on `main`).
- Produces:
  - `final class FoldPlaceholderView: NSView { var progress: Double }`
  - `final class OverlayPresenter { init?(); func update(_ state: FoldState) }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/LidRippleOverlayTests/FoldPlaceholderViewTests.swift`:

```swift
import Testing
import AppKit
@testable import LidRippleOverlay

@Test func settingProgressMarksTheViewForRedraw() {
    let view = FoldPlaceholderView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    view.needsDisplay = false
    view.progress = 0.5
    #expect(view.needsDisplay)
}

@Test func isNeverOpaque() {
    let view = FoldPlaceholderView(frame: .zero)
    #expect(!view.isOpaque)
}

@Test func progressDefaultsToZero() {
    let view = FoldPlaceholderView(frame: .zero)
    #expect(view.progress == 0)
}
```

Create `Tests/LidRippleOverlayTests/OverlayPresenterTests.swift`:

```swift
import Testing
import LidRippleCore
@testable import LidRippleOverlay

/// OverlayPresenter's init returns nil on hardware with no built-in display —
/// nothing to assert there beyond "it doesn't crash." On a MacBook it succeeds.
@Test func initSucceedsOrFailsWithoutCrashing() {
    _ = OverlayPresenter()
}

@Test func updateDoesNotCrashAcrossEveryPhase() {
    guard let presenter = OverlayPresenter() else { return }  // no built-in display here
    for phase in FoldPhase.allCases {
        presenter.update(FoldState(phase: phase, progress: 0.5, velocity: 0))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FoldPlaceholderViewTests` and `swift test --filter OverlayPresenterTests`
Expected: FAIL — `cannot find 'FoldPlaceholderView'`/`'OverlayPresenter' in scope`.

- [ ] **Step 3: Write `FoldPlaceholderView`**

Create `Sources/LidRippleOverlay/FoldPlaceholderView.swift`:

```swift
import AppKit

/// Stands in for Plan 2c's Metal-rendered fold view: a flat black rectangle whose
/// opacity tracks fold progress, just enough to see the overlay respond to a real
/// lid close before any shader exists.
public final class FoldPlaceholderView: NSView {
    public var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    public override var isOpaque: Bool { false }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        let alpha = CGFloat(min(max(progress, 0), 1))
        NSColor.black.withAlphaComponent(alpha).setFill()
        bounds.fill()
    }
}
```

- [ ] **Step 4: Write `OverlayPresenter`**

Create `Sources/LidRippleOverlay/OverlayPresenter.swift`:

```swift
import AppKit
import LidRippleCore

/// Owns the overlay window's show/hide lifecycle. Spec FR-1: nothing is drawn while
/// idle or armed. `folding`/`unfolding`/`sealed` all show the window — `sealed` holds
/// the final (fully-folded) frame on screen until the app tears it down.
public final class OverlayPresenter {
    private let window: OverlayWindow
    private let placeholderView: FoldPlaceholderView

    public init?() {
        guard let screen = BuiltInDisplay.screen() else { return nil }
        let view = FoldPlaceholderView(frame: screen.frame)
        self.placeholderView = view
        let window = OverlayWindow(screen: screen)
        window.contentView = view
        self.window = window
    }

    public func update(_ state: FoldState) {
        placeholderView.progress = state.progress
        switch state.phase {
        case .idle, .armed:
            window.orderOut(nil)
        case .folding, .unfolding, .sealed:
            window.orderFrontRegardless()
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter FoldPlaceholderViewTests` and `swift test --filter OverlayPresenterTests`
Expected: PASS, 3 and 2 tests respectively.

Then run the full suite: `swift test`
Expected: PASS, all tests (73 + 5 new = 78).

- [ ] **Step 6: Commit**

```bash
git add Sources/LidRippleOverlay/FoldPlaceholderView.swift Sources/LidRippleOverlay/OverlayPresenter.swift Tests/LidRippleOverlayTests/FoldPlaceholderViewTests.swift Tests/LidRippleOverlayTests/OverlayPresenterTests.swift
git commit -m "feat: add FoldPlaceholderView and OverlayPresenter

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 4: AppDelegate — wire sensor to driver to overlay

**Files:**
- Create: `Sources/LidRippleApp/AppDelegate.swift`
- Modify: `Sources/LidRippleApp/main.swift` (replace Task 1's placeholder)

**Interfaces:**
- Consumes: `FoldDriver`, `AngleSample` (`LidRippleCore`); `HIDAngleSource`, `SensorProbe`
  (`LidRippleSensor`); `OverlayPresenter` (`LidRippleOverlay`, this plan).
- Produces: `final class AppDelegate: NSObject, NSApplicationDelegate`. Nothing later in
  this plan consumes `AppDelegate` directly — it is the composition root.

This task has no automated test: it is pure wiring between already-tested pieces, and
its actual behavior (does a status item appear, does closing the lid show the overlay)
can only be observed by running the real app. Task 6 covers that manual verification.

- [ ] **Step 1: Write `AppDelegate`**

Create `Sources/LidRippleApp/AppDelegate.swift`:

```swift
import AppKit
import LidRippleCore
import LidRippleSensor
import LidRippleOverlay

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let driver = FoldDriver()
    private var sensor: HIDAngleSource?
    private var overlay: OverlayPresenter?
    private var scriptedUnfoldTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The LSUIElement effect (no Dock icon, no app menu) without needing an
        // app bundle or Info.plist — packaging arrives in M5.
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayPresenter()
        if overlay == nil {
            print("No built-in display on this Mac; the overlay is disabled.")
        }

        setUpStatusItem()
        observeWorkspaceNotifications()
        startSensorIfAvailable()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◐"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit lidripple", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startSensorIfAvailable() {
        let source = HIDAngleSource()
        guard source.isAvailable else {
            print(SensorProbe.probe().description)
            return
        }
        sensor = source
        do {
            try source.start { [weak self] sample in
                guard let self else { return }
                let state = self.driver.ingest(sample)
                DispatchQueue.main.async { self.overlay?.update(state) }
            }
        } catch {
            print("Failed to start the lid angle sensor: \(error)")
        }
    }

    private func observeWorkspaceNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        // Spec section 7.3 / FR-10: the scripted unfold triggers on session unlock,
        // which is a distributed (not NSWorkspace) notification.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenDidUnlock),
            name: Notification.Name("com.apple.screenIsUnlocked"), object: nil
        )
    }

    /// Spec section 10.1: a hard jump to sealed, tearing down anything in flight.
    @objc private func willSleep() {
        scriptedUnfoldTimer?.invalidate()
        let state = driver.signalSleep()
        overlay?.update(state)
    }

    /// Spec FR-10: unfold on unlock. This plan drives the placeholder view through
    /// the real FoldDriver timing; Plan 2c wires a fresh screen capture into the
    /// same call site once the renderer exists.
    @objc private func screenDidUnlock() {
        let state = driver.beginScriptedUnfold(now: ProcessInfo.processInfo.systemUptime)
        overlay?.update(state)

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let state = self.driver.tick(now: ProcessInfo.processInfo.systemUptime)
            self.overlay?.update(state)
            if state.phase == .idle {
                timer.invalidate()
            }
        }
        scriptedUnfoldTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
```

- [ ] **Step 2: Replace `main.swift`**

Replace `Sources/LidRippleApp/main.swift` entirely:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean build, zero errors, zero warnings.

- [ ] **Step 4: Run the full test suite to confirm no regression**

Run: `swift test`
Expected: PASS, all 78 tests (this task added none — see the note in Interfaces above).

- [ ] **Step 5: Commit**

```bash
git add Sources/LidRippleApp/AppDelegate.swift Sources/LidRippleApp/main.swift
git commit -m "feat: wire sensor, FoldDriver, and overlay into a running app

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 5: Manual verification — the actual de-risk for this plan

This plan's code compiles and unit-tests clean by Task 4, but nothing has confirmed the
*real* window-server behavior yet: does the overlay actually draw on top of everything,
stay off the Dock, and track a real lid close. This task is the equivalent of Task 2's
Step 6 in the M0-M1 plan — automate what can be automated, and honestly report what
needs a human.

**Files:** none — this task runs the app and observes it.

- [ ] **Step 1: Run the app in the foreground**

```bash
swift run LidRippleApp
```

Confirm, and **stop and report** if any fails:

1. **No Dock icon appears**, and no application menu bar (no "LidRippleApp" menu next to
   the Apple logo) — confirms `setActivationPolicy(.accessory)` is working.
2. **A status item appears** in the menu bar showing "◐", with a working "Quit
   lidripple" menu item.
3. **No window is visible** while the lid sits open and static (spec FR-1) — the overlay
   should be completely invisible at this point, not just transparent.

- [ ] **Step 2: Close the lid partway and confirm the overlay appears**

While `LidRippleApp` is running in the foreground (Step 1), close the lid slowly to
somewhere between 75° and 25° (per the M0-M1 `FoldTuning` thresholds already on `main`)
and confirm:

1. A darkening overlay appears, covering the built-in display, growing more opaque as
   the lid closes further.
2. It draws **above** other windows and, if you have a fullscreen app open, above that
   too.
3. Clicking through the overlay works — it must not intercept mouse events
   (`ignoresMouseEvents`).
4. Opening the lid back up fades the overlay back out and it disappears entirely once
   past the idle-return threshold (78°).

- [ ] **Step 3: External display check (only if one is available)**

If you have an external display connected, repeat Step 2 in clamshell-adjacent
conditions (external display attached, but lid not fully closed) and confirm the overlay
**never appears on the external display** — only ever on the built-in panel (spec
FR-13). If no external display is available to test with, note that explicitly in your
report rather than skipping the check silently.

- [ ] **Step 4: Sleep/wake behavior (optional, skip if inconvenient)**

If you're comfortable letting the machine sleep: close the lid all the way (machine
sleeps), then reopen it. Confirm the overlay does **not** show a stale mid-fold frame —
either it's invisible (most likely, since this plan has no scripted-unfold capture yet
and the placeholder view will just show whatever `driver.state.progress` was at sleep
time, frozen) or it briefly flashes and clears. This is expected to be visually rough at
this stage — Plan 2c's real capture and unfold make it look right. Report what you
actually saw; don't skip this step to avoid reporting an imperfect result, since an
imperfect-but-non-crashing result is expected and fine.

- [ ] **Step 5: Report**

Write a short summary of what you observed for each of the above, explicitly calling out
anything that didn't match the expected behavior, and anything you couldn't test (no
external display, didn't want to sleep the machine, etc.). This is the same honesty
standard as Task 2's sensor verification — report what you actually saw.

- [ ] **Step 6: No commit for this task** — it's verification only, no files changed.

---

## Definition of done

- [ ] `swift build` and `swift test` both pass from the repo root.
- [ ] `LidRippleOverlay` imports only `Foundation`, `AppKit`, `CoreGraphics`, and
      `LidRippleCore` — no `LidRippleSensor`.
- [ ] `LidRippleCore`, `LidRippleSensor`, `LidRippleTrace` are untouched by this plan.
- [ ] `OverlayWindow`'s configuration (level, collectionBehavior, ignoresMouseEvents,
      isOpaque, backgroundColor, hasShadow, styleMask) is asserted by unit test, not
      just eyeballed.
- [ ] Task 5's manual verification completed and reported honestly, including anything
      that couldn't be tested.
- [ ] No Metal, no ScreenCaptureKit, no TCC permission prompt anywhere in this plan.

## What Plan 2b covers

ScreenCaptureKit freeze-frame capture: `CaptureCoordinator` warms a low-fps stream while
`armed`, freezes to an `MTLTexture` at fold start, and stops it. It excludes this plan's
`OverlayWindow` from the capture filter (a real requirement now that the window exists).
This is where the first TCC permission prompt (Screen Recording) enters the project.
