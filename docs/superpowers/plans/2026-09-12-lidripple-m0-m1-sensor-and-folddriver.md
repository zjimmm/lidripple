# lidripple M0–M1: Sensor and FoldDriver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read the MacBook lid angle sensor at 60 Hz, record and replay lid traces as JSON, and build a pure `FoldDriver` that converts angle samples into fold progress with spring momentum, hysteresis, and a full phase machine — all proven by unit tests against replayed traces, with zero rendering code.

**Architecture:** A dependency-free Swift package with three libraries. `LidRippleCore` holds pure value types and the driver and imports nothing but Foundation. `LidRippleSensor` wraps IOKit HID. `LidRippleTrace` handles the JSON trace format. A hand-rolled CLI (`lidripple-trace`) exposes probe/record/replay so the sensor can be de-risked and real traces captured. All app-bundle concerns (Metal, ScreenCaptureKit, AppKit, TCC) are deliberately out of scope and arrive in Plan 2.

**Tech Stack:** Swift 6, Swift Package Manager, swift-testing (`import Testing`, bundled with the Swift 6 toolchain), IOKit/IOKit.hid. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-12-lidripple-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Platform floor: macOS 14.0.** Declare `platforms: [.macOS(.v14)]` in `Package.swift` (spec §6).
- **swift-tools-version: 6.0.**
- **Zero third-party dependencies.** The trust story in spec §11 rests on the source being auditable in an afternoon; every added dependency undercuts it. This is why the CLI argument parsing is hand-rolled rather than using swift-argument-parser.
- **No network access anywhere, ever** (spec §11). No `URLSession`, no sockets, no telemetry.
- **`LidRippleCore` imports only `Foundation`.** Spec §8.1 makes "depends on nothing" the load-bearing property of `FoldDriver`. No IOKit, no AppKit, no Metal in that target. A reviewer should reject any task that adds one.
- **All tuning constants live in `FoldTuning` and nowhere else** (spec §9.4). No magic numbers in driver, filter, or spring code — they read values from the struct they are handed.
- **Exact threshold values, copied verbatim from spec §9:** arm 110°, fold start 75°, fold end 25°, seal 12°, idle return 78°, direction velocity threshold 5°/s, direction hold 50 ms, filter cutoff 15 Hz, deadband 0.3°, stiffness 220, damping 26, feed-forward 0.06, max progress 1.06, spring substep 1/240 s, squash exponent gain 1.8, rotation 72°, blur radius 28 px, blur progress exponent 2.0, void speed 1.15, void softness 0.28, rim width 0.012, rim intensity 0.35.
- **Build and test from repo root:** `swift build`, `swift test`.
- **Commit style:** conventional commits. Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq
  ```
- **Do not create `LICENSE`.** Spec §16 pins it to M5.

## Deviations from the spec, with rationale

Two refinements this plan adds. Both are noted here rather than buried, because they change documented behavior.

1. **Velocity is smoothed at 8 Hz before the direction gate** (`velocitySmoothingHz`). Spec §9.2 filters *angle* at 15 Hz, but the raw derivative of that signal at 60 Hz still passes enough noise to cross the 5°/s gate: a 15 Hz one-pole at 60 Hz has α ≈ 0.79, so ±0.25° of sensor jitter yields ±0.2° per sample, which is ±12°/s. Without smoothing, resting a hand on the lid can trip a direction change.
2. **The direction gate additionally requires net travel ≥ 0.8°** (`directionMinTravelDegrees`). The spec's own numbers do not close: 5°/s sustained for 50 ms is only 0.25° of travel, which is inside the noise floor. Requiring real displacement makes jitter structurally incapable of committing a direction. Consequence, accepted deliberately: a very slow reversal (near 5°/s) registers in ~160 ms rather than 50 ms. A reversal that slow is not perceptually urgent, and fast reversals still register within ~5 ms of travel.

---

## File Structure

| File | Responsibility |
|---|---|
| `Package.swift` | Package manifest: 3 libraries, 1 executable, 2 test targets |
| `.gitignore` | SPM build artifacts only; Xcode entries arrive in Plan 2 |
| `Sources/LidRippleCore/AngleSample.swift` | Immutable `(degrees, timestamp)` value type |
| `Sources/LidRippleCore/LidAngleSource.swift` | Protocol: the seam for fakes and trace replay |
| `Sources/LidRippleCore/FoldTuning.swift` | All ~24 constants, `Codable`, partial JSON override, intensity |
| `Sources/LidRippleCore/AngleFilter.swift` | One-pole angle filter, deadband, smoothed velocity |
| `Sources/LidRippleCore/Spring.swift` | Fixed-substep second-order integrator |
| `Sources/LidRippleCore/FoldState.swift` | `FoldPhase` enum and `FoldState` output value type |
| `Sources/LidRippleCore/FoldDriver.swift` | The pure phase machine; the product's feel |
| `Sources/LidRippleSensor/HIDAngleSource.swift` | IOKit HID reader, 60 Hz polling |
| `Sources/LidRippleSensor/SensorProbe.swift` | Presence check and human-readable diagnostics |
| `Sources/LidRippleTrace/Trace.swift` | `Codable` trace format |
| `Sources/LidRippleTrace/TraceRecorder.swift` | Accumulates samples into a `Trace` |
| `Sources/LidRippleTrace/TraceReplaySource.swift` | Real-time replay conforming to `LidAngleSource` |
| `Sources/LidRippleTrace/TraceGenerator.swift` | Deterministic synthetic traces for fixtures |
| `Sources/lidripple-trace/main.swift` | CLI: `probe`, `record`, `replay`, `info` |
| `Tests/LidRippleCoreTests/*` | Filter, spring, tuning, phase, and trace-regression tests |
| `Tests/LidRippleTraceTests/*` | Trace codec tests plus committed JSON fixtures |

---

## Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/LidRippleCore/AngleSample.swift`
- Create: `Sources/LidRippleCore/LidAngleSource.swift`
- Create: `Sources/LidRippleSensor/SensorProbe.swift` (placeholder enum, filled in Task 2)
- Create: `Sources/LidRippleTrace/Trace.swift` (placeholder, filled in Task 8)
- Create: `Sources/lidripple-trace/main.swift` (placeholder, filled in Task 10)
- Test: `Tests/LidRippleCoreTests/AngleSampleTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `AngleSample(degrees: Double, timestamp: TimeInterval)`; protocol `LidAngleSource` with `var isAvailable: Bool`, `func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws`, `func stop()`.

- [ ] **Step 1: Create `.gitignore`**

Only SPM artifacts. Xcode entries are added in Plan 2 alongside the Xcode project, because adding them before the project exists invites committing `xcuserstate` by accident.

```gitignore
.build/
.swiftpm/
.DS_Store
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "lidripple",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LidRippleCore", targets: ["LidRippleCore"]),
        .library(name: "LidRippleSensor", targets: ["LidRippleSensor"]),
        .library(name: "LidRippleTrace", targets: ["LidRippleTrace"]),
        .executable(name: "lidripple-trace", targets: ["lidripple-trace"]),
    ],
    targets: [
        .target(name: "LidRippleCore"),
        .target(name: "LidRippleSensor", dependencies: ["LidRippleCore"]),
        .target(name: "LidRippleTrace", dependencies: ["LidRippleCore"]),
        .executableTarget(
            name: "lidripple-trace",
            dependencies: ["LidRippleCore", "LidRippleSensor", "LidRippleTrace"]
        ),
        .testTarget(
            name: "LidRippleCoreTests",
            dependencies: ["LidRippleCore", "LidRippleSensor", "LidRippleTrace"]
        ),
        .testTarget(name: "LidRippleTraceTests", dependencies: ["LidRippleTrace", "LidRippleCore"]),
    ]
)
```

- [ ] **Step 3: Write the failing test**

Create `Tests/LidRippleCoreTests/AngleSampleTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleCore

@Test func angleSampleStoresDegreesAndTimestamp() {
    let sample = AngleSample(degrees: 92.5, timestamp: 1.25)
    #expect(sample.degrees == 92.5)
    #expect(sample.timestamp == 1.25)
}

@Test func angleSamplesWithIdenticalValuesAreEqual() {
    #expect(AngleSample(degrees: 90, timestamp: 0) == AngleSample(degrees: 90, timestamp: 0))
    #expect(AngleSample(degrees: 90, timestamp: 0) != AngleSample(degrees: 91, timestamp: 0))
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `swift test --filter AngleSampleTests`
Expected: FAIL — compile error, `cannot find 'AngleSample' in scope`.

- [ ] **Step 5: Write the minimal implementation**

Create `Sources/LidRippleCore/AngleSample.swift`:

```swift
import Foundation

/// One reading from a lid angle source.
///
/// `degrees` is the physical lid angle: 0 is fully closed, and MacBook lids
/// open to roughly 135 degrees. `timestamp` is monotonic seconds from an
/// arbitrary origin; only differences between samples are meaningful.
public struct AngleSample: Equatable, Sendable {
    public let degrees: Double
    public let timestamp: TimeInterval

    public init(degrees: Double, timestamp: TimeInterval) {
        self.degrees = degrees
        self.timestamp = timestamp
    }
}
```

Create `Sources/LidRippleCore/LidAngleSource.swift`:

```swift
import Foundation

/// A stream of lid angle samples.
///
/// This protocol is the seam that keeps `FoldDriver` testable: the real
/// hardware source, a replayed trace, and a hand-built fake are
/// interchangeable behind it.
public protocol LidAngleSource: AnyObject, Sendable {
    /// Whether this source can actually produce samples on this machine.
    /// Checking must not prompt the user or open the device.
    var isAvailable: Bool { get }

    /// Begin delivering samples. The handler may be called on any thread.
    func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws

    /// Stop delivering samples. Safe to call when not started.
    func stop()
}
```

- [ ] **Step 6: Create the remaining placeholders so the package builds**

Create `Sources/LidRippleSensor/SensorProbe.swift`:

```swift
import Foundation

/// Filled in by Task 2.
public enum SensorProbe {}
```

Create `Sources/LidRippleTrace/Trace.swift`:

```swift
import Foundation

/// Filled in by Task 8.
public enum TracePlaceholder {}
```

Create `Sources/lidripple-trace/main.swift`:

```swift
// Filled in by Task 10.
print("lidripple-trace: not implemented yet")
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter AngleSampleTests`
Expected: PASS, 2 tests.

Also run: `swift build`
Expected: builds with no errors.

- [ ] **Step 8: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: scaffold lidripple Swift package with AngleSample and LidAngleSource

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 2: Lid angle sensor — the de-risk task

Spec §15 names this the project's top risk: some macOS versions may gate `IOHIDDeviceOpen` behind Input Monitoring, which would change the entire permissions story in §11. Retire that risk before investing in anything else. The raw-to-degrees scale factor is also unverified — spec §4 documents 16-bit values at 0.01° precision, so `raw / 100.0` is the expected mapping, but **confirm it empirically in Step 6** and adjust the single constant if it is wrong.

**Files:**
- Create: `Sources/LidRippleSensor/HIDAngleSource.swift`
- Modify: `Sources/LidRippleSensor/SensorProbe.swift` (replace the Task 1 placeholder)
- Test: `Tests/LidRippleCoreTests/SensorProbeTests.swift`

**Interfaces:**
- Consumes: `AngleSample`, `LidAngleSource` from Task 1.
- Produces:
  - `final class HIDAngleSource: LidAngleSource` with `init(pollHz: Double = 60, rawToDegrees: Double = 0.01)`.
  - `enum HIDAngleSourceError: Error { case deviceNotFound, elementNotFound, openFailed(Int32), alreadyStarted }`
  - `enum SensorProbe { static func probe() -> Report }`
  - `struct SensorProbe.Report { let isPresent: Bool; let vendorID: Int; let productID: Int; let description: String }`

- [ ] **Step 1: Write the failing test**

Hardware cannot be unit tested, so test the two things that must hold on **every** machine — including the sensor-less Macs that spec §7.4 must support. The critical property is that absence is reported, never thrown or crashed.

Create `Tests/LidRippleCoreTests/SensorProbeTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleSensor
@testable import LidRippleCore

@Test func probeReportsWithoutCrashingOnAnyHardware() {
    let report = SensorProbe.probe()
    #expect(report.vendorID == 0x05AC)
    #expect(report.productID == 0x8104)
    #expect(!report.description.isEmpty)
}

@Test func isAvailableNeverThrowsAndMatchesProbe() {
    let source = HIDAngleSource()
    #expect(source.isAvailable == SensorProbe.probe().isPresent)
}

@Test func startOnASensorlessMachineThrowsDeviceNotFound() throws {
    let source = HIDAngleSource()
    guard !source.isAvailable else { return }  // sensor-equipped machine: nothing to assert here
    #expect(throws: HIDAngleSourceError.deviceNotFound) {
        try source.start { _ in }
    }
}

@Test func stopIsSafeWhenNeverStarted() {
    HIDAngleSource().stop()  // must not crash
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SensorProbeTests`
Expected: FAIL — `cannot find 'HIDAngleSource' in scope`.

- [ ] **Step 3: Write the implementation**

Replace `Sources/LidRippleSensor/SensorProbe.swift` entirely:

```swift
import Foundation
import IOKit
import IOKit.hid

/// Hardware identifiers for Apple's internal lid angle sensor.
///
/// Documented in spec section 4: Apple vendor 0x05AC, product 0x8104,
/// HID sensor page 0x0020, orientation usage 0x008A.
public enum LidSensorIdentifiers {
    public static let vendorID = 0x05AC
    public static let productID = 0x8104
    public static let usagePage = 0x0020
    public static let usage = 0x008A
}

/// Non-invasive presence check. Must never prompt the user.
public enum SensorProbe {
    public struct Report: Sendable {
        public let isPresent: Bool
        public let vendorID: Int
        public let productID: Int
        public let description: String
    }

    public static func probe() -> Report {
        let present = matchingDevice() != nil
        let description = present
            ? "Lid angle sensor found (vendor 0x05AC, product 0x8104)."
            : """
              No lid angle sensor found. This is expected on desktop Macs and on \
              several M1/M2 MacBook Air and 13-inch MacBook Pro configurations. \
              lidripple will use the timed fallback driver.
              """
        return Report(
            isPresent: present,
            vendorID: LidSensorIdentifiers.vendorID,
            productID: LidSensorIdentifiers.productID,
            description: description
        )
    }

    /// Returns the matched device, or nil. Opens the *manager* but never the
    /// device, which is what keeps this from triggering a permission prompt.
    static func matchingDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Any] = [
            kIOHIDVendorIDKey: LidSensorIdentifiers.vendorID,
            kIOHIDProductIDKey: LidSensorIdentifiers.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        return devices.first
    }
}
```

Create `Sources/LidRippleSensor/HIDAngleSource.swift`:

```swift
import Foundation
import IOKit
import IOKit.hid
import LidRippleCore

public enum HIDAngleSourceError: Error, Equatable {
    case deviceNotFound
    case elementNotFound
    case openFailed(Int32)
    case alreadyStarted
}

/// Reads the internal lid angle sensor by polling its HID element.
///
/// Polling rather than an input-report callback is deliberate: the sensor does
/// not push reports on change, so a value read on a timer is the only way to
/// get a steady cadence.
public final class HIDAngleSource: LidAngleSource, @unchecked Sendable {
    private let pollHz: Double
    private let rawToDegrees: Double
    private let queue = DispatchQueue(label: "com.lidripple.sensor", qos: .userInteractive)

    private var device: IOHIDDevice?
    private var element: IOHIDElement?
    private var timer: DispatchSourceTimer?

    /// - Parameters:
    ///   - pollHz: sample cadence. Spec section 4 specifies 60 Hz.
    ///   - rawToDegrees: scale from the sensor's 16-bit integer to degrees.
    ///     Expected 0.01 per spec section 4; verify empirically (Task 2, Step 6).
    public init(pollHz: Double = 60, rawToDegrees: Double = 0.01) {
        self.pollHz = pollHz
        self.rawToDegrees = rawToDegrees
    }

    public var isAvailable: Bool { SensorProbe.matchingDevice() != nil }

    public func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws {
        guard timer == nil else { throw HIDAngleSourceError.alreadyStarted }
        guard let device = SensorProbe.matchingDevice() else { throw HIDAngleSourceError.deviceNotFound }

        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw HIDAngleSourceError.openFailed(status) }

        let elementCriteria: [String: Any] = [
            kIOHIDElementUsagePageKey: LidSensorIdentifiers.usagePage,
            kIOHIDElementUsageKey: LidSensorIdentifiers.usage,
        ]
        guard
            let elements = IOHIDDeviceCopyMatchingElements(
                device, elementCriteria as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)
            ) as? [IOHIDElement],
            let element = elements.first
        else {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            throw HIDAngleSourceError.elementNotFound
        }

        self.device = device
        self.element = element

        let interval = 1.0 / pollHz
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in
            guard let self, let sample = self.read() else { return }
            handler(sample)
        }
        timer = source
        source.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        element = nil
    }

    private func read() -> AngleSample? {
        guard let device, let element else { return nil }
        var valueRef: Unmanaged<IOHIDValue>?
        guard IOHIDDeviceGetValue(device, element, &valueRef) == kIOReturnSuccess,
              let value = valueRef?.takeUnretainedValue()
        else { return nil }
        let degrees = Double(IOHIDValueGetIntegerValue(value)) * rawToDegrees
        return AngleSample(degrees: degrees, timestamp: ProcessInfo.processInfo.systemUptime)
    }
}
```

- [ ] **Step 4: Add a temporary `probe` command so the sensor can be observed**

Replace `Sources/lidripple-trace/main.swift` (Task 10 replaces this again with the full CLI):

```swift
import Foundation
import LidRippleCore
import LidRippleSensor

let report = SensorProbe.probe()
print(report.description)
guard report.isPresent else { exit(0) }

let source = HIDAngleSource()
try source.start { sample in
    print(String(format: "%8.2f deg  t=%.3f", sample.degrees, sample.timestamp))
}
print("Polling at 60 Hz. Move the lid. Ctrl-C to stop.")
RunLoop.main.run()
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter SensorProbeTests`
Expected: PASS, 4 tests, on a sensor-equipped **and** a sensor-less machine.

- [ ] **Step 6: Manual verification — this is the actual de-risk**

Run: `swift run lidripple-trace`

Confirm all five, and **stop and report** if any fails:

1. **Angles print at roughly 60 lines/second** and change smoothly as you move the lid.
2. **The scale factor is correct.** Open the lid to a visually square right angle and confirm the printed value is near 90, not near 9000 or 0.9. If it is off by a power of ten, change `rawToDegrees` in `HIDAngleSource.init` — that one constant is the only thing that needs to change.
3. **Fully closed reads near 0** and your normal working angle reads somewhere in 90–130.
4. **No Input Monitoring prompt appeared.** Then check System Settings → Privacy & Security → Input Monitoring and confirm `lidripple-trace` is **not** listed. This is the spec §15 risk; if a prompt did appear, stop and report, because §11's permission claims need rewriting before continuing.
5. **No crash on Ctrl-C**, and rerunning works (proves `stop()` and `IOHIDDeviceClose` are balanced).

- [ ] **Step 7: Record the verified scale factor in the spec**

Add one line to spec §4 under the hardware reference stating the empirically confirmed scale factor and the machine it was confirmed on. The spec currently states the precision but not a verified mapping.

- [ ] **Step 8: Commit**

```bash
git add Sources/LidRippleSensor Sources/lidripple-trace Tests/LidRippleCoreTests/SensorProbeTests.swift docs/superpowers/specs
git commit -m "feat: read the lid angle sensor over IOKit HID at 60 Hz

Retires the top risk in spec section 15: confirms IOHIDDeviceOpen on
sensor usage page 0x0020 needs no Input Monitoring permission, and
verifies the raw-to-degrees scale factor empirically.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 3: FoldTuning

**Files:**
- Create: `Sources/LidRippleCore/FoldTuning.swift`
- Test: `Tests/LidRippleCoreTests/FoldTuningTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct FoldTuning: Codable, Equatable, Sendable` with `static let `default`: FoldTuning`, `func withIntensity(_ intensity: Double) -> FoldTuning`, `mutating func apply(overrides: [String: Double]) throws`, `static func loading(overridesAt url: URL) throws -> FoldTuning`, and `enum FoldTuningError: Error { case unknownKey(String) }`.

Property names used by later tasks, exactly: `armAngle`, `foldStartAngle`, `foldEndAngle`, `sealAngle`, `idleReturnAngle`, `phaseHysteresisDegrees`, `directionVelocityThreshold`, `directionHoldSeconds`, `directionMinTravelDegrees`, `filterCutoffHz`, `velocitySmoothingHz`, `deadbandDegrees`, `stiffness`, `damping`, `feedForward`, `maxProgress`, `substepSeconds`, `scriptedUnfoldSeconds`, `squashExponentGain`, `rotationDegrees`, `blurRadiusPx`, `blurProgressExponent`, `voidSpeed`, `voidSoftness`, `rimWidth`, `rimIntensity`, `intensity`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleCoreTests/FoldTuningTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleCore

@Test func defaultsMatchTheSpec() {
    let t = FoldTuning.default
    #expect(t.armAngle == 110)
    #expect(t.foldStartAngle == 75)
    #expect(t.foldEndAngle == 25)
    #expect(t.sealAngle == 12)
    #expect(t.idleReturnAngle == 78)
    #expect(t.directionVelocityThreshold == 5)
    #expect(t.directionHoldSeconds == 0.050)
    #expect(t.filterCutoffHz == 15)
    #expect(t.deadbandDegrees == 0.3)
    #expect(t.stiffness == 220)
    #expect(t.damping == 26)
    #expect(t.feedForward == 0.06)
    #expect(t.maxProgress == 1.06)
    #expect(t.substepSeconds == 1.0 / 240.0)
    #expect(t.rotationDegrees == 72)
    #expect(t.blurRadiusPx == 28)
    #expect(t.voidSpeed == 1.15)
    #expect(t.intensity == 1.0)
}

@Test func idleReturnIsAboveFoldStartByTheHysteresisGap() {
    let t = FoldTuning.default
    #expect(t.idleReturnAngle - t.foldStartAngle == t.phaseHysteresisDegrees)
}

@Test func intensityScalesOnlyTheThreeRenderTerms() {
    let base = FoldTuning.default
    let soft = base.withIntensity(0.5)

    // Scaled, per spec FR-17.
    #expect(soft.blurRadiusPx == base.blurRadiusPx * 0.5)
    #expect(soft.rotationDegrees == base.rotationDegrees * 0.5)
    #expect(soft.squashExponentGain == base.squashExponentGain * 0.5)

    // Untouched: timing, thresholds, spring.
    #expect(soft.foldStartAngle == base.foldStartAngle)
    #expect(soft.foldEndAngle == base.foldEndAngle)
    #expect(soft.stiffness == base.stiffness)
    #expect(soft.damping == base.damping)
    #expect(soft.substepSeconds == base.substepSeconds)
    #expect(soft.directionHoldSeconds == base.directionHoldSeconds)
}

@Test func intensityClampsToTheSupportedRange() {
    #expect(FoldTuning.default.withIntensity(0.1).intensity == 0.5)
    #expect(FoldTuning.default.withIntensity(9.0).intensity == 1.0)
}

@Test func partialOverridesLeaveEverythingElseAtDefault() throws {
    var t = FoldTuning.default
    try t.apply(overrides: ["stiffness": 300, "blurRadiusPx": 40])
    #expect(t.stiffness == 300)
    #expect(t.blurRadiusPx == 40)
    #expect(t.damping == FoldTuning.default.damping)
    #expect(t.foldStartAngle == FoldTuning.default.foldStartAngle)
}

@Test func unknownOverrideKeyIsRejectedRatherThanIgnored() {
    var t = FoldTuning.default
    #expect(throws: FoldTuningError.unknownKey("stifness")) {
        try t.apply(overrides: ["stifness": 300])
    }
}

@Test func roundTripsThroughJSON() throws {
    let original = FoldTuning.default.withIntensity(0.75)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(FoldTuning.self, from: data)
    #expect(decoded == original)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FoldTuningTests`
Expected: FAIL — `cannot find 'FoldTuning' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/LidRippleCore/FoldTuning.swift`:

```swift
import Foundation

public enum FoldTuningError: Error, Equatable {
    case unknownKey(String)
}

/// Every tunable constant in lidripple, in one place.
///
/// Spec section 9.4 requires this: tuning the animation must be a data change,
/// not a rebuild. No other type in the package may hard-code any of these.
public struct FoldTuning: Codable, Equatable, Sendable {
    // MARK: Phase thresholds (degrees)
    public var armAngle: Double = 110
    public var foldStartAngle: Double = 75
    public var foldEndAngle: Double = 25
    public var sealAngle: Double = 12
    public var idleReturnAngle: Double = 78
    /// Gap between fold entry (75) and idle return (78). Spec section 9.2.
    public var phaseHysteresisDegrees: Double = 3

    // MARK: Direction detection
    public var directionVelocityThreshold: Double = 5      // degrees/second
    public var directionHoldSeconds: Double = 0.050
    /// Net travel required to commit a direction. Plan deviation 2.
    public var directionMinTravelDegrees: Double = 0.8

    // MARK: Filtering
    public var filterCutoffHz: Double = 15
    /// Velocity smoothing. Plan deviation 1.
    public var velocitySmoothingHz: Double = 8
    public var deadbandDegrees: Double = 0.3

    // MARK: Spring
    public var stiffness: Double = 220
    public var damping: Double = 26
    public var feedForward: Double = 0.06
    public var maxProgress: Double = 1.06
    public var substepSeconds: Double = 1.0 / 240.0

    // MARK: Scripted unfold on unlock (spec FR-10)
    public var scriptedUnfoldSeconds: Double = 0.620

    // MARK: Render (consumed in Plan 2; defined here so section 9.4 holds)
    public var squashExponentGain: Double = 1.8
    public var rotationDegrees: Double = 72
    public var blurRadiusPx: Double = 28
    public var blurProgressExponent: Double = 2.0
    public var voidSpeed: Double = 1.15
    public var voidSoftness: Double = 0.28
    public var rimWidth: Double = 0.012
    public var rimIntensity: Double = 0.35

    // MARK: User control
    public var intensity: Double = 1.0

    public init() {}

    public static let `default` = FoldTuning()

    /// Applies the user intensity control. Spec FR-17: scales exactly blur
    /// radius, rotation, and squash exponent; never timing, thresholds, or
    /// the spring.
    public func withIntensity(_ intensity: Double) -> FoldTuning {
        let clamped = min(max(intensity, 0.5), 1.0)
        var copy = self
        copy.intensity = clamped
        copy.blurRadiusPx = FoldTuning.default.blurRadiusPx * clamped
        copy.rotationDegrees = FoldTuning.default.rotationDegrees * clamped
        copy.squashExponentGain = FoldTuning.default.squashExponentGain * clamped
        return copy
    }

    /// Applies a sparse set of overrides, e.g. from a hot-reloaded JSON file.
    /// Unknown keys throw rather than being ignored, so a typo in a tuning
    /// file surfaces immediately instead of silently doing nothing.
    public mutating func apply(overrides: [String: Double]) throws {
        for (key, value) in overrides {
            switch key {
            case "armAngle": armAngle = value
            case "foldStartAngle": foldStartAngle = value
            case "foldEndAngle": foldEndAngle = value
            case "sealAngle": sealAngle = value
            case "idleReturnAngle": idleReturnAngle = value
            case "phaseHysteresisDegrees": phaseHysteresisDegrees = value
            case "directionVelocityThreshold": directionVelocityThreshold = value
            case "directionHoldSeconds": directionHoldSeconds = value
            case "directionMinTravelDegrees": directionMinTravelDegrees = value
            case "filterCutoffHz": filterCutoffHz = value
            case "velocitySmoothingHz": velocitySmoothingHz = value
            case "deadbandDegrees": deadbandDegrees = value
            case "stiffness": stiffness = value
            case "damping": damping = value
            case "feedForward": feedForward = value
            case "maxProgress": maxProgress = value
            case "substepSeconds": substepSeconds = value
            case "scriptedUnfoldSeconds": scriptedUnfoldSeconds = value
            case "squashExponentGain": squashExponentGain = value
            case "rotationDegrees": rotationDegrees = value
            case "blurRadiusPx": blurRadiusPx = value
            case "blurProgressExponent": blurProgressExponent = value
            case "voidSpeed": voidSpeed = value
            case "voidSoftness": voidSoftness = value
            case "rimWidth": rimWidth = value
            case "rimIntensity": rimIntensity = value
            case "intensity": intensity = value
            default: throw FoldTuningError.unknownKey(key)
            }
        }
    }

    /// Loads defaults with a JSON override file applied on top.
    public static func loading(overridesAt url: URL) throws -> FoldTuning {
        let data = try Data(contentsOf: url)
        let overrides = try JSONDecoder().decode([String: Double].self, from: data)
        var tuning = FoldTuning.default
        try tuning.apply(overrides: overrides)
        return tuning
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FoldTuningTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/LidRippleCore/FoldTuning.swift Tests/LidRippleCoreTests/FoldTuningTests.swift
git commit -m "feat: add FoldTuning with all constants, intensity, and JSON overrides

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 4: AngleFilter

**Files:**
- Create: `Sources/LidRippleCore/AngleFilter.swift`
- Test: `Tests/LidRippleCoreTests/AngleFilterTests.swift`

**Interfaces:**
- Consumes: `AngleSample` (Task 1), `FoldTuning` (Task 3).
- Produces: `struct AngleFilter` with `init(tuning: FoldTuning)`, `mutating func process(_ sample: AngleSample) -> Double` returning the deadbanded committed angle, and `var velocity: Double { get }` in degrees/second (negative = closing).

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleCoreTests/AngleFilterTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleCore

/// Feeds a filter a sequence of angles at a fixed rate.
private func feed(
    _ filter: inout AngleFilter,
    angles: [Double],
    hz: Double = 60,
    startingAt t0: TimeInterval = 0
) -> [Double] {
    var out: [Double] = []
    for (i, deg) in angles.enumerated() {
        out.append(filter.process(AngleSample(degrees: deg, timestamp: t0 + Double(i) / hz)))
    }
    return out
}

@Test func firstSampleIsPassedThroughWithZeroVelocity() {
    var filter = AngleFilter(tuning: .default)
    let committed = filter.process(AngleSample(degrees: 91.4, timestamp: 0))
    #expect(committed == 91.4)
    #expect(filter.velocity == 0)
}

@Test func constantInputSettlesToThatValueWithZeroVelocity() {
    var filter = AngleFilter(tuning: .default)
    let out = feed(&filter, angles: Array(repeating: 90, count: 60))
    #expect(abs(out.last! - 90) < 0.001)
    #expect(abs(filter.velocity) < 0.1)
}

@Test func aStepIsSmoothedRatherThanJumped() {
    var filter = AngleFilter(tuning: .default)
    _ = feed(&filter, angles: Array(repeating: 90, count: 30))
    let out = feed(&filter, angles: Array(repeating: 60, count: 2), startingAt: 0.5)
    // 15 Hz one-pole at 60 Hz has alpha ~= 0.79, so a 30 degree step must not
    // arrive whole on the first sample.
    #expect(out[0] > 60.5)
    #expect(out[0] < 90)
}

@Test func subDeadbandJitterNeverMovesTheCommittedAngle() {
    var filter = AngleFilter(tuning: .default)
    var angles = [90.0]
    // Deterministic alternating jitter well inside the 0.3 degree deadband.
    for i in 0..<120 { angles.append(90 + (i % 2 == 0 ? 0.12 : -0.12)) }
    let out = feed(&filter, angles: angles)
    #expect(out.allSatisfy { $0 == 90.0 })
}

@Test func jitterAtRestKeepsSmoothedVelocityBelowTheDirectionGate() {
    var filter = AngleFilter(tuning: .default)
    var angles = [90.0]
    for i in 0..<120 { angles.append(90 + (i % 2 == 0 ? 0.25 : -0.25)) }
    _ = feed(&filter, angles: angles)
    // This is plan deviation 1: without velocity smoothing this exceeds 5.
    #expect(abs(filter.velocity) < FoldTuning.default.directionVelocityThreshold)
}

@Test func steadyRampConvergesToTheRampRate() {
    var filter = AngleFilter(tuning: .default)
    let ratePerSecond = -120.0            // closing at 120 deg/s
    let angles = (0..<90).map { 110 + ratePerSecond * Double($0) / 60.0 }
    _ = feed(&filter, angles: angles)
    #expect(abs(filter.velocity - ratePerSecond) < 6.0)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AngleFilterTests`
Expected: FAIL — `cannot find 'AngleFilter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/LidRippleCore/AngleFilter.swift`:

```swift
import Foundation

/// Conditions a raw sensor stream into something a state machine can trust.
///
/// Three jobs, per spec section 9.2 and plan deviation 1:
///  - one-pole low-pass on angle, removing sensor noise
///  - a deadband on the output, so micro-movement does not move the committed
///    angle at all
///  - a separately smoothed velocity estimate, because the raw derivative of a
///    15 Hz-filtered signal at 60 Hz still crosses the 5 deg/s direction gate
///    on noise alone
public struct AngleFilter {
    private let cutoffHz: Double
    private let velocitySmoothingHz: Double
    private let deadband: Double

    private var filtered: Double?
    private var committed: Double = 0
    private var lastTimestamp: TimeInterval?

    /// Degrees per second. Negative means closing.
    public private(set) var velocity: Double = 0

    public init(tuning: FoldTuning) {
        self.cutoffHz = tuning.filterCutoffHz
        self.velocitySmoothingHz = tuning.velocitySmoothingHz
        self.deadband = tuning.deadbandDegrees
    }

    /// Returns the committed (deadbanded) angle for this sample.
    public mutating func process(_ sample: AngleSample) -> Double {
        guard let previous = filtered, let previousTime = lastTimestamp else {
            filtered = sample.degrees
            committed = sample.degrees
            lastTimestamp = sample.timestamp
            velocity = 0
            return committed
        }

        let dt = max(sample.timestamp - previousTime, 1e-6)
        let angleAlpha = 1 - exp(-2 * .pi * cutoffHz * dt)
        let next = previous + angleAlpha * (sample.degrees - previous)

        let instantaneous = (next - previous) / dt
        let velocityAlpha = 1 - exp(-2 * .pi * velocitySmoothingHz * dt)
        velocity += velocityAlpha * (instantaneous - velocity)

        filtered = next
        lastTimestamp = sample.timestamp

        if abs(next - committed) > deadband {
            committed = next
        }
        return committed
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AngleFilterTests`
Expected: PASS, 6 tests.

If `jitterAtRestKeepsSmoothedVelocityBelowTheDirectionGate` fails, lower `velocitySmoothingHz` in `FoldTuning` — do not weaken the assertion. That test is the whole reason plan deviation 1 exists.

- [ ] **Step 5: Commit**

```bash
git add Sources/LidRippleCore/AngleFilter.swift Tests/LidRippleCoreTests/AngleFilterTests.swift
git commit -m "feat: add AngleFilter with deadband and smoothed velocity

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 5: Spring

**Files:**
- Create: `Sources/LidRippleCore/Spring.swift`
- Test: `Tests/LidRippleCoreTests/SpringTests.swift`

**Interfaces:**
- Consumes: `FoldTuning` (Task 3).
- Produces: `struct Spring` with `init(tuning: FoldTuning, value: Double = 0)`, `mutating func step(target: Double, dt: TimeInterval)`, `mutating func reset(to value: Double)`, `var value: Double { get }`, `var velocity: Double { get }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleCoreTests/SpringTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleCore

@Test func settlesToItsTarget() {
    var spring = Spring(tuning: .default)
    for _ in 0..<120 { spring.step(target: 1.0, dt: 1.0 / 60.0) }
    #expect(abs(spring.value - 1.0) < 0.001)
    #expect(abs(spring.velocity) < 0.01)
}

@Test func overshootStaysWithinTheSpecMaximum() {
    var spring = Spring(tuning: .default)
    var peak = 0.0
    for _ in 0..<240 {
        spring.step(target: 1.0, dt: 1.0 / 60.0)
        peak = max(peak, spring.value)
    }
    // zeta = 26 / (2 * sqrt(220)) ~= 0.877, so unit-step overshoot is under 1%.
    #expect(peak > 1.0)
    #expect(peak < FoldTuning.default.maxProgress)
}

@Test func lagsBehindTheTargetRatherThanTrackingItExactly() {
    var spring = Spring(tuning: .default)
    spring.step(target: 1.0, dt: 1.0 / 60.0)
    #expect(spring.value < 0.2)      // this lag is what makes slow closes feel viscous
    #expect(spring.value > 0)
}

@Test func largeTimestepsStayStableBecauseOfFixedSubstepping() {
    var spring = Spring(tuning: .default)
    // A 250 ms hitch would explode a naive single-step Euler integrator.
    for _ in 0..<20 { spring.step(target: 1.0, dt: 0.25) }
    #expect(spring.value.isFinite)
    #expect(abs(spring.value - 1.0) < 0.01)
}

@Test func substeppingMakesTheResultIndependentOfSampleRate() {
    var at60 = Spring(tuning: .default)
    var at120 = Spring(tuning: .default)
    for _ in 0..<60 { at60.step(target: 1.0, dt: 1.0 / 60.0) }
    for _ in 0..<120 { at120.step(target: 1.0, dt: 1.0 / 120.0) }
    #expect(abs(at60.value - at120.value) < 0.01)
}

@Test func resetClearsValueAndVelocity() {
    var spring = Spring(tuning: .default)
    for _ in 0..<10 { spring.step(target: 1.0, dt: 1.0 / 60.0) }
    spring.reset(to: 0)
    #expect(spring.value == 0)
    #expect(spring.velocity == 0)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SpringTests`
Expected: FAIL — `cannot find 'Spring' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/LidRippleCore/Spring.swift`:

```swift
import Foundation

/// A damped second-order system integrated at a fixed substep.
///
/// Spec section 9.1: the lid angle supplies the *target*, and this chases it.
/// That indirection is what produces viscous slow closes, continuous
/// reversal, and jitter absorption from one mechanism.
///
/// Substepping at a fixed interval rather than the incoming `dt` matters: the
/// sensor cadence is not guaranteed, and semi-implicit Euler at 220 stiffness
/// diverges on a long frame.
public struct Spring {
    private let stiffness: Double
    private let damping: Double
    private let substep: Double

    public private(set) var value: Double
    public private(set) var velocity: Double = 0

    public init(tuning: FoldTuning, value: Double = 0) {
        self.stiffness = tuning.stiffness
        self.damping = tuning.damping
        self.substep = tuning.substepSeconds
        self.value = value
    }

    public mutating func step(target: Double, dt: TimeInterval) {
        guard dt > 0 else { return }
        var remaining = dt
        while remaining > 0 {
            let h = min(substep, remaining)
            let acceleration = stiffness * (target - value) - damping * velocity
            velocity += acceleration * h
            value += velocity * h
            remaining -= h
        }
    }

    public mutating func reset(to value: Double) {
        self.value = value
        self.velocity = 0
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SpringTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/LidRippleCore/Spring.swift Tests/LidRippleCoreTests/SpringTests.swift
git commit -m "feat: add fixed-substep spring integrator

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 6: FoldState and the phase machine

**Files:**
- Create: `Sources/LidRippleCore/FoldState.swift`
- Create: `Sources/LidRippleCore/FoldDriver.swift`
- Test: `Tests/LidRippleCoreTests/FoldDriverPhaseTests.swift`

**Interfaces:**
- Consumes: `AngleSample`, `FoldTuning`, `AngleFilter`, `Spring`.
- Produces:
  - `enum FoldPhase: String, Codable, Sendable, CaseIterable { case idle, armed, folding, unfolding, sealed }`
  - `struct FoldState: Equatable, Sendable { let phase: FoldPhase; let progress: Double; let velocity: Double }`
  - `final class FoldDriver` with `init(tuning: FoldTuning = .default)`, `var state: FoldState { get }`, `@discardableResult func ingest(_ sample: AngleSample) -> FoldState`, `@discardableResult func signalSleep() -> FoldState`, `@discardableResult func reset() -> FoldState`.

`tick(now:)` and `beginScriptedUnfold(now:)` are added in Task 7. This task builds phases only; progress stays 0 throughout so the transitions can be tested in isolation.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleCoreTests/FoldDriverPhaseTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleCore

/// Drives a driver from `from` to `to` degrees at a given rate, 60 Hz.
/// Returns every state produced, so tests can assert on the whole trajectory.
@discardableResult
private func sweep(
    _ driver: FoldDriver,
    from: Double,
    to: Double,
    degreesPerSecond: Double,
    startingAt t0: TimeInterval
) -> (states: [FoldState], endTime: TimeInterval) {
    let hz = 60.0
    let step = degreesPerSecond / hz * (to > from ? 1 : -1)
    var angle = from
    var t = t0
    var states: [FoldState] = []
    while (to > from && angle < to) || (to < from && angle > to) {
        angle += step
        t += 1 / hz
        states.append(driver.ingest(AngleSample(degrees: angle, timestamp: t)))
    }
    return (states, t)
}

/// Holds a constant angle, which is how a direction gate gets time to expire.
@discardableResult
private func hold(
    _ driver: FoldDriver,
    at angle: Double,
    seconds: Double,
    startingAt t0: TimeInterval
) -> TimeInterval {
    var t = t0
    for _ in 0..<Int(seconds * 60) {
        t += 1 / 60.0
        driver.ingest(AngleSample(degrees: angle, timestamp: t))
    }
    return t
}

@Test func startsIdle() {
    #expect(FoldDriver().state.phase == .idle)
}

@Test func aSingleSampleBelowArmAngleDoesNotArm() {
    let driver = FoldDriver()
    // No previous sample means no velocity, so intent cannot be established.
    driver.ingest(AngleSample(degrees: 100, timestamp: 0))
    #expect(driver.state.phase == .idle)
}

@Test func sustainedClosingBelowArmAngleArms() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 100, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .armed)
}

@Test func armedBecomesFoldingBelowFoldStart() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 70, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .folding)
}

@Test func foldingBecomesSealedBelowSealAngle() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 8, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .sealed)
}

@Test func aSingleOpeningSampleDoesNotReverseTheFold() {
    let driver = FoldDriver()
    let (_, t) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .folding)
    // One sample of opening is noise, not intent.
    driver.ingest(AngleSample(degrees: 50.5, timestamp: t + 1 / 60.0))
    #expect(driver.state.phase == .folding)
}

@Test func sustainedOpeningReversesTheFold() {
    let driver = FoldDriver()
    let (_, t) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    sweep(driver, from: 50, to: 62, degreesPerSecond: 120, startingAt: t)
    #expect(driver.state.phase == .unfolding)
}

@Test func unfoldingDoesNotReturnToIdleBelowTheHysteresisThreshold() {
    let driver = FoldDriver()
    let (_, t1) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    let (_, t2) = sweep(driver, from: 50, to: 77, degreesPerSecond: 120, startingAt: t1)
    // 77 is above fold start (75) but below idle return (78).
    hold(driver, at: 77, seconds: 0.6, startingAt: t2)
    #expect(driver.state.phase == .unfolding)
}

@Test func unfoldingReturnsToIdleAboveTheHysteresisThreshold() {
    let driver = FoldDriver()
    let (_, t1) = sweep(driver, from: 120, to: 50, degreesPerSecond: 120, startingAt: 0)
    let (_, t2) = sweep(driver, from: 50, to: 85, degreesPerSecond: 120, startingAt: t1)
    hold(driver, at: 85, seconds: 0.6, startingAt: t2)
    #expect(driver.state.phase == .idle)
    #expect(driver.state.progress == 0)
}

@Test func jitterAtRestNeverChangesPhase() {
    let driver = FoldDriver()
    var t = 0.0
    for i in 0..<600 {
        t += 1 / 60.0
        driver.ingest(AngleSample(degrees: 90 + (i % 2 == 0 ? 0.25 : -0.25), timestamp: t))
        #expect(driver.state.phase == .idle)
    }
}

@Test func sleepSignalSealsFromAnyPhase() {
    for endAngle in [90.0, 100.0, 50.0] {
        let driver = FoldDriver()
        sweep(driver, from: 130, to: endAngle, degreesPerSecond: 120, startingAt: 0)
        let state = driver.signalSleep()
        #expect(state.phase == .sealed)
        #expect(state.progress == 1.0)
    }
}

@Test func resetReturnsToIdleWithZeroProgress() {
    let driver = FoldDriver()
    sweep(driver, from: 120, to: 40, degreesPerSecond: 120, startingAt: 0)
    let state = driver.reset()
    #expect(state.phase == .idle)
    #expect(state.progress == 0)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FoldDriverPhaseTests`
Expected: FAIL — `cannot find 'FoldDriver' in scope`.

- [ ] **Step 3: Write `FoldState`**

Create `Sources/LidRippleCore/FoldState.swift`:

```swift
import Foundation

public enum FoldPhase: String, Codable, Sendable, CaseIterable {
    /// Lid open and static. Nothing captured, nothing drawn.
    case idle
    /// Closing intent detected. Capture warms; still nothing drawn.
    case armed
    /// The fold is running forward.
    case folding
    /// The fold is running backward, tracking the lid.
    case unfolding
    /// Fully folded. Holds the final frame until teardown.
    case sealed
}

public struct FoldState: Equatable, Sendable {
    public let phase: FoldPhase
    /// 0 is fully unfolded, 1 is fully folded. May slightly exceed 1 up to
    /// `FoldTuning.maxProgress`; the renderer reads the excess as extra void.
    public let progress: Double
    /// Rate of change of `progress`, per second.
    public let velocity: Double

    public init(phase: FoldPhase, progress: Double, velocity: Double) {
        self.phase = phase
        self.progress = progress
        self.velocity = velocity
    }

    public static let idle = FoldState(phase: .idle, progress: 0, velocity: 0)
}
```

- [ ] **Step 4: Write `FoldDriver` with phases only**

Create `Sources/LidRippleCore/FoldDriver.swift`:

```swift
import Foundation

/// Converts lid angle samples into fold state.
///
/// This type is the product's feel, and per spec section 8.1 it imports only
/// Foundation: no IOKit, no Metal, no AppKit. That is what makes the animation
/// testable from recorded traces instead of by closing a laptop repeatedly.
public final class FoldDriver {
    private let tuning: FoldTuning
    private var filter: AngleFilter
    private var spring: Spring

    private var phase: FoldPhase = .idle
    private var lastTimestamp: TimeInterval?

    /// Direction gate: tracks how long motion has been consistently one way
    /// and how far it has travelled. Both must clear before a direction
    /// commits (spec section 9.2 plus plan deviation 2).
    private var gateIsClosing = false
    private var gateSince: TimeInterval?
    private var gateStartAngle: Double?

    public private(set) var state: FoldState = .idle

    public init(tuning: FoldTuning = .default) {
        self.tuning = tuning
        self.filter = AngleFilter(tuning: tuning)
        self.spring = Spring(tuning: tuning)
    }

    @discardableResult
    public func ingest(_ sample: AngleSample) -> FoldState {
        let angle = filter.process(sample)
        let velocity = filter.velocity
        let dt = lastTimestamp.map { max(sample.timestamp - $0, 0) } ?? 0
        lastTimestamp = sample.timestamp

        updateDirectionGate(angle: angle, velocity: velocity, now: sample.timestamp)
        advancePhase(angle: angle)
        return publish(angle: angle, velocity: velocity, dt: dt)
    }

    @discardableResult
    public func signalSleep() -> FoldState {
        phase = .sealed
        spring.reset(to: 1.0)
        state = FoldState(phase: .sealed, progress: 1.0, velocity: 0)
        return state
    }

    @discardableResult
    public func reset() -> FoldState {
        phase = .idle
        spring.reset(to: 0)
        filter = AngleFilter(tuning: tuning)
        lastTimestamp = nil
        clearGate()
        state = .idle
        return state
    }

    // MARK: - Direction gate

    private func updateDirectionGate(angle: Double, velocity: Double, now: TimeInterval) {
        let closing = velocity < -tuning.directionVelocityThreshold
        let opening = velocity > tuning.directionVelocityThreshold

        guard closing || opening else { clearGate(); return }

        if gateSince == nil || gateIsClosing != closing {
            gateIsClosing = closing
            gateSince = now
            gateStartAngle = angle
        }
    }

    private func clearGate() {
        gateSince = nil
        gateStartAngle = nil
    }

    /// True when motion has been consistently in `closing` direction for long
    /// enough *and* travelled far enough to be real rather than noise.
    private func directionCommitted(closing: Bool, angle: Double, now: TimeInterval) -> Bool {
        guard gateIsClosing == closing,
              let since = gateSince,
              let start = gateStartAngle,
              now - since >= tuning.directionHoldSeconds,
              abs(angle - start) >= tuning.directionMinTravelDegrees
        else { return false }
        return true
    }

    // MARK: - Phase machine

    private func advancePhase(angle: Double) {
        let now = lastTimestamp ?? 0
        switch phase {
        case .idle:
            if angle < tuning.armAngle, directionCommitted(closing: true, angle: angle, now: now) {
                phase = .armed
            }
        case .armed:
            if angle < tuning.foldStartAngle {
                phase = .folding
            } else if angle > tuning.armAngle + tuning.phaseHysteresisDegrees,
                      directionCommitted(closing: false, angle: angle, now: now) {
                phase = .idle
            }
        case .folding:
            if angle < tuning.sealAngle {
                phase = .sealed
                spring.reset(to: 1.0)
            } else if directionCommitted(closing: false, angle: angle, now: now) {
                phase = .unfolding
            }
        case .unfolding:
            if directionCommitted(closing: true, angle: angle, now: now) {
                phase = .folding
            } else if spring.value <= 0.001, angle > tuning.idleReturnAngle {
                phase = .idle
                spring.reset(to: 0)
            }
        case .sealed:
            break  // only signalSleep, reset, or the unlock path leave sealed
        }
    }

    // MARK: - Output

    /// Task 6 keeps progress pinned to the phase so transitions can be tested
    /// in isolation. Task 7 replaces this with the spring-driven version.
    private func publish(angle: Double, velocity: Double, dt: TimeInterval) -> FoldState {
        let progress: Double
        switch phase {
        case .idle, .armed: progress = 0
        case .sealed: progress = 1.0
        case .folding, .unfolding: progress = spring.value
        }
        state = FoldState(phase: phase, progress: progress, velocity: 0)
        return state
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter FoldDriverPhaseTests`
Expected: PASS, 12 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/LidRippleCore/FoldState.swift Sources/LidRippleCore/FoldDriver.swift Tests/LidRippleCoreTests/FoldDriverPhaseTests.swift
git commit -m "feat: add FoldDriver phase machine with hysteresis and direction gating

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 7: Progress — spring, feed-forward, and the scripted unfold

**Files:**
- Modify: `Sources/LidRippleCore/FoldDriver.swift` (replace `publish`, add `tick` and `beginScriptedUnfold`)
- Test: `Tests/LidRippleCoreTests/FoldDriverProgressTests.swift`

**Interfaces:**
- Consumes: everything from Task 6.
- Produces, added to `FoldDriver`:
  - `@discardableResult func tick(now: TimeInterval) -> FoldState` — advances the spring with no new angle sample. Used for the scripted unfold and for rendering at a display rate above the 60 Hz sensor rate.
  - `@discardableResult func beginScriptedUnfold(now: TimeInterval) -> FoldState` — spec FR-10: unfold over `tuning.scriptedUnfoldSeconds` with no angle input.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleCoreTests/FoldDriverProgressTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleCore

/// Sweeps and returns the peak progress seen, which is what most of these
/// tests actually care about.
private func sweepTrackingPeak(
    _ driver: FoldDriver,
    from: Double,
    to: Double,
    degreesPerSecond: Double,
    startingAt t0: TimeInterval
) -> (peak: Double, endTime: TimeInterval) {
    let hz = 60.0
    let step = degreesPerSecond / hz * (to > from ? 1 : -1)
    var angle = from
    var t = t0
    var peak = 0.0
    while (to > from && angle < to) || (to < from && angle > to) {
        angle += step
        t += 1 / hz
        peak = max(peak, driver.ingest(AngleSample(degrees: angle, timestamp: t)).progress)
    }
    return (peak, t)
}

@Test func progressIsZeroWhileIdleAndArmed() {
    let driver = FoldDriver()
    let (peak, _) = sweepTrackingPeak(driver, from: 130, to: 80, degreesPerSecond: 120, startingAt: 0)
    #expect(driver.state.phase == .armed)
    #expect(peak == 0)
}

@Test func aFullSlowCloseReachesFullProgress() {
    let driver = FoldDriver()
    // 40 deg/s is the spec's viscous case.
    sweepTrackingPeak(driver, from: 120, to: 15, degreesPerSecond: 40, startingAt: 0)
    #expect(driver.state.progress > 0.99)
}

@Test func progressNeverExceedsTheSpecMaximum() {
    for rate in [40.0, 120.0, 300.0, 600.0] {
        let driver = FoldDriver()
        let (peak, _) = sweepTrackingPeak(driver, from: 130, to: 5, degreesPerSecond: rate, startingAt: 0)
        #expect(peak <= FoldTuning.default.maxProgress + 1e-9, "rate \(rate) overshot to \(peak)")
    }
}

@Test func aFastCloseLeadsTheLidBecauseOfFeedForward() {
    let slow = FoldDriver()
    let fast = FoldDriver()
    // Stop both at the same angle; the faster close should be further along.
    sweepTrackingPeak(slow, from: 120, to: 50, degreesPerSecond: 40, startingAt: 0)
    sweepTrackingPeak(fast, from: 120, to: 50, degreesPerSecond: 400, startingAt: 0)
    #expect(fast.state.progress > slow.state.progress)
}

@Test func reversingMidCloseNeverReachesFullProgress() {
    let driver = FoldDriver()
    let (peakIn, t) = sweepTrackingPeak(driver, from: 120, to: 40, degreesPerSecond: 120, startingAt: 0)
    #expect(peakIn < 1.0)
    let (_, t2) = sweepTrackingPeak(driver, from: 40, to: 95, degreesPerSecond: 120, startingAt: t)
    // Settle at the open angle.
    var t3 = t2
    for _ in 0..<60 { t3 += 1 / 60.0; driver.ingest(AngleSample(degrees: 95, timestamp: t3)) }
    #expect(driver.state.phase == .idle)
    #expect(driver.state.progress == 0)
}

@Test func progressIsMonotonicDuringASteadyClose() {
    let driver = FoldDriver()
    var previous = -1.0
    var angle = 120.0
    var t = 0.0
    var sawDecrease = false
    while angle > 20 {
        angle -= 2
        t += 1 / 60.0
        let p = driver.ingest(AngleSample(degrees: angle, timestamp: t)).progress
        if p < previous - 1e-9 { sawDecrease = true }
        previous = p
    }
    #expect(!sawDecrease)
}

@Test func tickAdvancesProgressWithoutNewSamples() {
    let driver = FoldDriver()
    let (_, t) = sweepTrackingPeak(driver, from: 120, to: 40, degreesPerSecond: 120, startingAt: 0)
    let before = driver.state.progress
    var now = t
    for _ in 0..<10 { now += 1 / 120.0; driver.tick(now: now) }
    // The spring is still chasing the target set by the last real sample.
    #expect(driver.state.progress > before)
}

@Test func scriptedUnfoldRunsFromSealedToZeroInExactlyTheSpecifiedTime() {
    let driver = FoldDriver()
    driver.signalSleep()
    #expect(driver.state.progress == 1.0)

    var now = 100.0
    driver.beginScriptedUnfold(now: now)
    #expect(driver.state.phase == .unfolding)

    let duration = FoldTuning.default.scriptedUnfoldSeconds

    // Smoothstep is symmetric, so halfway through time is halfway through progress.
    while now < 100 + duration / 2 { now += 1 / 240.0; driver.tick(now: now) }
    #expect(abs(driver.state.progress - 0.5) < 0.05)
    #expect(driver.state.velocity < 0)

    // At the deadline it is finished outright, with no spring tail.
    while now < 100 + duration + 1 / 60.0 { now += 1 / 240.0; driver.tick(now: now) }
    #expect(driver.state.phase == .idle)
    #expect(driver.state.progress == 0)
}

@Test func velocityIsReportedAndOppositelySignedInEachDirection() {
    let driver = FoldDriver()
    let (_, t) = sweepTrackingPeak(driver, from: 120, to: 50, degreesPerSecond: 200, startingAt: 0)
    #expect(driver.state.velocity > 0)      // folding: progress increasing
    sweepTrackingPeak(driver, from: 50, to: 70, degreesPerSecond: 200, startingAt: t)
    #expect(driver.state.velocity < 0)      // unfolding: progress decreasing
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FoldDriverProgressTests`
Expected: FAIL — `value of type 'FoldDriver' has no member 'tick'`, plus progress assertions failing because Task 6's `publish` never advances the spring.

- [ ] **Step 3: Replace `publish` and add the new entry points**

In `Sources/LidRippleCore/FoldDriver.swift`, add two stored properties next to the existing ones:

```swift
    /// Set while a scripted (angle-free) unfold is running. Spec FR-10.
    private var scriptedUnfoldStart: TimeInterval?
    private var lastTarget: Double = 0
```

Replace the whole `publish(angle:velocity:dt:)` method with:

```swift
    /// Spec section 9.1: the lid supplies the target, the spring supplies the
    /// output. Feed-forward is expressed in progress units per second so it is
    /// dimensionally consistent with `u`.
    private func publish(angle: Double, velocity: Double, dt: TimeInterval) -> FoldState {
        let span = tuning.foldStartAngle - tuning.foldEndAngle
        let u = min(max((tuning.foldStartAngle - angle) / span, 0), 1)
        let normalizedRate = -velocity / span            // progress units per second
        let target = min(max(u + tuning.feedForward * normalizedRate, 0), tuning.maxProgress)
        lastTarget = target

        switch phase {
        case .idle, .armed:
            spring.reset(to: 0)
            state = FoldState(phase: phase, progress: 0, velocity: 0)
        case .sealed:
            state = FoldState(phase: .sealed, progress: 1.0, velocity: 0)
        case .folding, .unfolding:
            spring.step(target: target, dt: dt)
            state = FoldState(
                phase: phase,
                progress: min(max(spring.value, 0), tuning.maxProgress),
                velocity: spring.velocity
            )
        }
        return state
    }

    /// Advances the spring toward the last computed target without a new angle
    /// sample. Two uses: the scripted unfold, which has no angle input at all,
    /// and rendering at a display rate higher than the 60 Hz sensor rate.
    @discardableResult
    public func tick(now: TimeInterval) -> FoldState {
        let dt = lastTimestamp.map { max(now - $0, 0) } ?? 0
        lastTimestamp = now
        guard dt > 0 else { return state }

        if let start = scriptedUnfoldStart {
            // The spring is deliberately bypassed here. Spec FR-10 wants a definite
            // 620 ms, and pushing a linear ramp through a 220/26 spring lags it by
            // rate * damping / stiffness, about 0.19 progress, which would stretch
            // the reveal past 900 ms and leave a visible tail. With no lid to track
            // there is nothing for the spring to buy, so drive the curve directly.
            let fraction = min(max((now - start) / tuning.scriptedUnfoldSeconds, 0), 1)
            let eased = fraction * fraction * (3 - 2 * fraction)   // smoothstep
            let progress = 1.0 - eased
            lastTarget = progress
            spring.reset(to: progress)   // keep spring state coherent for any later ingest
            if fraction >= 1 {
                scriptedUnfoldStart = nil
                phase = .idle
                spring.reset(to: 0)
                state = .idle
                return state
            }
            state = FoldState(
                phase: .unfolding,
                progress: progress,
                velocity: -6 * fraction * (1 - fraction) / tuning.scriptedUnfoldSeconds
            )
            return state
        }

        switch phase {
        case .folding, .unfolding:
            spring.step(target: lastTarget, dt: dt)
            state = FoldState(
                phase: phase,
                progress: min(max(spring.value, 0), tuning.maxProgress),
                velocity: spring.velocity
            )
        default:
            break
        }
        return state
    }

    /// Spec FR-10: after the session unlocks, unfold a freshly captured frame
    /// on a timed curve. The lid is already open, so there is no angle to
    /// track and `tick(now:)` drives this to completion.
    @discardableResult
    public func beginScriptedUnfold(now: TimeInterval) -> FoldState {
        phase = .unfolding
        scriptedUnfoldStart = now
        lastTimestamp = now
        spring.reset(to: 1.0)
        clearGate()
        state = FoldState(phase: .unfolding, progress: 1.0, velocity: 0)
        return state
    }
```

Also add `scriptedUnfoldStart = nil` and `lastTarget = 0` to the body of `reset()`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FoldDriverProgressTests`
Expected: PASS, 9 tests.

Then run the full suite to confirm Task 6's phase tests still hold:
Run: `swift test`
Expected: PASS, all tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/LidRippleCore/FoldDriver.swift Tests/LidRippleCoreTests/FoldDriverProgressTests.swift
git commit -m "feat: drive fold progress with spring momentum and feed-forward

Adds tick() for angle-free advancement and beginScriptedUnfold() for the
post-unlock path in spec FR-10.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 8: Trace format and recorder

**Files:**
- Modify: `Sources/LidRippleTrace/Trace.swift` (replace the Task 1 placeholder)
- Create: `Sources/LidRippleTrace/TraceRecorder.swift`
- Test: `Tests/LidRippleTraceTests/TraceTests.swift`

**Interfaces:**
- Consumes: `AngleSample` (Task 1).
- Produces:
  - `struct Trace: Codable, Equatable, Sendable` with `let name: String`, `let recordedAt: Date`, `let deviceModel: String`, `let samples: [Trace.Sample]`, and nested `struct Sample: Codable, Equatable, Sendable { let t: Double; let deg: Double }`.
  - `Trace.init(name:recordedAt:deviceModel:samples:)`
  - `var angleSamples: [AngleSample] { get }` — samples rebased so the first timestamp is 0.
  - `func encoded() throws -> Data`, `static func decoded(from: Data) throws -> Trace`
  - `final class TraceRecorder` with `init(name: String, deviceModel: String)`, `func record(_ sample: AngleSample)`, `func finish(at: Date) -> Trace`, `var count: Int { get }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleTraceTests/TraceTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleTrace
@testable import LidRippleCore

@Test func roundTripsThroughJSON() throws {
    let trace = Trace(
        name: "slow-close",
        recordedAt: Date(timeIntervalSince1970: 1_789_000_000),
        deviceModel: "MacBookPro18,3",
        samples: [.init(t: 0, deg: 95.25), .init(t: 1.0 / 60.0, deg: 94.5)]
    )
    let decoded = try Trace.decoded(from: try trace.encoded())
    #expect(decoded == trace)
}

@Test func encodedJSONUsesTheShortStableKeys() throws {
    let trace = Trace(
        name: "x", recordedAt: Date(timeIntervalSince1970: 0), deviceModel: "m",
        samples: [.init(t: 0.5, deg: 90)]
    )
    let json = String(decoding: try trace.encoded(), as: UTF8.self)
    // A trace is tens of thousands of samples; short keys keep fixtures readable.
    #expect(json.contains("\"t\""))
    #expect(json.contains("\"deg\""))
}

@Test func angleSamplesAreRebasedToStartAtZero() {
    let trace = Trace(
        name: "x", recordedAt: Date(), deviceModel: "m",
        samples: [.init(t: 5000.0, deg: 95), .init(t: 5000.5, deg: 90)]
    )
    let samples = trace.angleSamples
    #expect(samples[0].timestamp == 0)
    #expect(abs(samples[1].timestamp - 0.5) < 1e-12)
    #expect(samples[0].degrees == 95)
}

@Test func anEmptyTraceProducesNoSamples() {
    let trace = Trace(name: "x", recordedAt: Date(), deviceModel: "m", samples: [])
    #expect(trace.angleSamples.isEmpty)
}

@Test func recorderAccumulatesSamplesInOrder() {
    let recorder = TraceRecorder(name: "slam", deviceModel: "MacBookPro18,3")
    recorder.record(AngleSample(degrees: 95, timestamp: 10))
    recorder.record(AngleSample(degrees: 90, timestamp: 10.5))
    #expect(recorder.count == 2)

    let trace = recorder.finish(at: Date(timeIntervalSince1970: 0))
    #expect(trace.name == "slam")
    #expect(trace.deviceModel == "MacBookPro18,3")
    #expect(trace.samples.map(\.deg) == [95, 90])
    #expect(trace.samples.map(\.t) == [10, 10.5])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TraceTests`
Expected: FAIL — `cannot find 'Trace' in scope`.

- [ ] **Step 3: Write the implementation**

Replace `Sources/LidRippleTrace/Trace.swift` entirely:

```swift
import Foundation
import LidRippleCore

/// A recorded sequence of real lid angles.
///
/// Spec section 12 makes this the project's highest-value test
/// infrastructure: it is the only way to exercise the driver against genuine
/// hand motion deterministically and repeatedly.
public struct Trace: Codable, Equatable, Sendable {
    public struct Sample: Codable, Equatable, Sendable {
        public let t: Double
        public let deg: Double

        public init(t: Double, deg: Double) {
            self.t = t
            self.deg = deg
        }
    }

    public let name: String
    public let recordedAt: Date
    public let deviceModel: String
    public let samples: [Sample]

    public init(name: String, recordedAt: Date, deviceModel: String, samples: [Sample]) {
        self.name = name
        self.recordedAt = recordedAt
        self.deviceModel = deviceModel
        self.samples = samples
    }

    /// Samples as driver input, rebased so the first timestamp is 0. Recorded
    /// timestamps come from `systemUptime` and are large and machine-specific;
    /// rebasing makes fixtures comparable across machines.
    public var angleSamples: [AngleSample] {
        guard let first = samples.first else { return [] }
        return samples.map { AngleSample(degrees: $0.deg, timestamp: $0.t - first.t) }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> Trace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Trace.self, from: data)
    }
}
```

Create `Sources/LidRippleTrace/TraceRecorder.swift`:

```swift
import Foundation
import LidRippleCore

/// Accumulates live samples into a `Trace`.
public final class TraceRecorder {
    private let name: String
    private let deviceModel: String
    private let lock = NSLock()
    private var samples: [Trace.Sample] = []

    public init(name: String, deviceModel: String) {
        self.name = name
        self.deviceModel = deviceModel
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    /// Safe to call from the sensor's polling queue.
    public func record(_ sample: AngleSample) {
        lock.lock(); defer { lock.unlock() }
        samples.append(Trace.Sample(t: sample.timestamp, deg: sample.degrees))
    }

    public func finish(at date: Date = Date()) -> Trace {
        lock.lock(); defer { lock.unlock() }
        return Trace(name: name, recordedAt: date, deviceModel: deviceModel, samples: samples)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TraceTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/LidRippleTrace Tests/LidRippleTraceTests
git commit -m "feat: add Trace format and TraceRecorder

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 9: Trace replay and synthetic generation

**Files:**
- Create: `Sources/LidRippleTrace/TraceReplaySource.swift`
- Create: `Sources/LidRippleTrace/TraceGenerator.swift`
- Test: `Tests/LidRippleTraceTests/TraceReplayTests.swift`

**Interfaces:**
- Consumes: `Trace` (Task 8), `LidAngleSource`, `AngleSample`.
- Produces:
  - `final class TraceReplaySource: LidAngleSource` with `init(trace: Trace, speed: Double = 1.0)` — real-time replay honoring inter-sample gaps.
  - `enum TraceGenerator` with `static func slowClose() -> Trace`, `slam()`, `hesitantClose()`, `stopAndReopen()`, `wiggleAtRest()`, `closeReopenClose()`, and `static var all: [Trace]`.

Synthetic traces exist so this plan's tests are runnable on a machine with no sensor and so results are byte-identical everywhere. Real recordings from `lidripple-trace record` are added as extra fixtures in M4 when tuning against genuine hand motion.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleTraceTests/TraceReplayTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleTrace
@testable import LidRippleCore

@Test func generatedTracesAreDeterministic() {
    #expect(TraceGenerator.slowClose() == TraceGenerator.slowClose())
    #expect(TraceGenerator.wiggleAtRest() == TraceGenerator.wiggleAtRest())
}

@Test func allSixCanonicalTracesExistAndAreNamed() {
    let names = Set(TraceGenerator.all.map(\.name))
    #expect(names == [
        "slow-close", "slam", "hesitant-close",
        "stop-and-reopen", "wiggle-at-rest", "close-reopen-close",
    ])
}

@Test func everyGeneratedTraceHasMonotonicTimestampsAndPlausibleAngles() {
    for trace in TraceGenerator.all {
        #expect(!trace.samples.isEmpty, "\(trace.name) is empty")
        for (a, b) in zip(trace.samples, trace.samples.dropFirst()) {
            #expect(b.t > a.t, "\(trace.name) has non-monotonic time")
        }
        for sample in trace.samples {
            #expect(sample.deg >= 0 && sample.deg <= 140, "\(trace.name) angle out of range")
        }
    }
}

@Test func slamIsMuchShorterThanSlowCloseForTheSameTravel() {
    let slow = TraceGenerator.slowClose()
    let slam = TraceGenerator.slam()
    let slowDuration = slow.samples.last!.t - slow.samples.first!.t
    let slamDuration = slam.samples.last!.t - slam.samples.first!.t
    #expect(slamDuration < slowDuration / 5)
}

@Test func wiggleAtRestStaysWithinAFractionOfADegree() {
    let samples = TraceGenerator.wiggleAtRest().samples
    let angles = samples.map(\.deg)
    #expect(angles.max()! - angles.min()! < 1.0)
}

@Test func replaySourceDeliversEverySampleInOrder() async throws {
    let trace = Trace(
        name: "tiny", recordedAt: Date(), deviceModel: "test",
        samples: (0..<20).map { .init(t: Double($0) / 60.0, deg: 100 - Double($0)) }
    )
    // 200x speed keeps the test fast while still exercising the timing path.
    let source = TraceReplaySource(trace: trace, speed: 200)
    let box = Box()
    try source.start { sample in box.append(sample) }

    let deadline = Date().addingTimeInterval(3)
    while box.count < 20, Date() < deadline {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    source.stop()

    #expect(box.count == 20)
    #expect(box.degrees == (0..<20).map { 100 - Double($0) })
}

/// Minimal thread-safe collector, since the handler may fire off-thread.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [AngleSample] = []
    func append(_ s: AngleSample) { lock.lock(); samples.append(s); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }
    var degrees: [Double] { lock.lock(); defer { lock.unlock() }; return samples.map(\.degrees) }
}

@Test func replaySourceIsAlwaysAvailable() {
    #expect(TraceReplaySource(trace: TraceGenerator.slam()).isAvailable)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TraceReplayTests`
Expected: FAIL — `cannot find 'TraceGenerator' in scope`.

- [ ] **Step 3: Write `TraceGenerator`**

Create `Sources/LidRippleTrace/TraceGenerator.swift`:

```swift
import Foundation
import LidRippleCore

/// Deterministic synthetic lid traces.
///
/// These cover the six motions named in spec section 12 and are generated
/// rather than recorded so the suite runs identically on any machine,
/// including one with no lid sensor.
public enum TraceGenerator {
    private static let hz = 60.0
    private static let epoch = Date(timeIntervalSince1970: 1_789_000_000)

    public static var all: [Trace] {
        [slowClose(), slam(), hesitantClose(), stopAndReopen(), wiggleAtRest(), closeReopenClose()]
    }

    /// 120 degrees to 5 at 40 deg/s: the viscous case.
    public static func slowClose() -> Trace {
        build("slow-close", segments: [.ramp(from: 120, to: 5, degreesPerSecond: 40)])
    }

    /// 120 degrees to 5 at 600 deg/s: faster than the eye, tests the clamp.
    public static func slam() -> Trace {
        build("slam", segments: [.ramp(from: 120, to: 5, degreesPerSecond: 600)])
    }

    /// Closing in three bursts with pauses, the way someone half-distracted does it.
    public static func hesitantClose() -> Trace {
        build("hesitant-close", segments: [
            .ramp(from: 115, to: 80, degreesPerSecond: 150),
            .hold(at: 80, seconds: 0.30),
            .ramp(from: 80, to: 45, degreesPerSecond: 90),
            .hold(at: 45, seconds: 0.40),
            .ramp(from: 45, to: 6, degreesPerSecond: 200),
        ])
    }

    /// Closes to 45, changes mind, opens back up. The reversal case.
    public static func stopAndReopen() -> Trace {
        build("stop-and-reopen", segments: [
            .ramp(from: 110, to: 45, degreesPerSecond: 160),
            .hold(at: 45, seconds: 0.15),
            .ramp(from: 45, to: 100, degreesPerSecond: 160),
            .hold(at: 100, seconds: 0.50),
        ])
    }

    /// A hand resting on an open lid: two seconds of sub-degree noise.
    /// Deterministic by construction, no RNG.
    public static func wiggleAtRest() -> Trace {
        var samples: [Trace.Sample] = []
        let count = Int(2.0 * hz)
        for i in 0..<count {
            let wobble = 0.22 * sin(Double(i) * 0.9) + 0.10 * sin(Double(i) * 2.7)
            samples.append(Trace.Sample(t: Double(i) / hz, deg: 90 + wobble))
        }
        return Trace(name: "wiggle-at-rest", recordedAt: epoch, deviceModel: "synthetic", samples: samples)
    }

    /// Close, reopen partway, close again. Exercises re-entrancy.
    public static func closeReopenClose() -> Trace {
        build("close-reopen-close", segments: [
            .ramp(from: 110, to: 40, degreesPerSecond: 180),
            .ramp(from: 40, to: 95, degreesPerSecond: 180),
            // 0.45 s, not 0.20: the spring needs ~0.3 s to settle to zero, and
            // Task 10 asserts this trace genuinely passes through idle.
            .hold(at: 95, seconds: 0.45),
            .ramp(from: 95, to: 5, degreesPerSecond: 180),
        ])
    }

    // MARK: - Building blocks

    private enum Segment {
        case ramp(from: Double, to: Double, degreesPerSecond: Double)
        case hold(at: Double, seconds: Double)
    }

    private static func build(_ name: String, segments: [Segment]) -> Trace {
        var samples: [Trace.Sample] = []
        var t = 0.0
        for segment in segments {
            switch segment {
            case let .ramp(from, to, rate):
                let steps = max(Int((abs(to - from) / rate) * hz), 1)
                for i in 1...steps {
                    let fraction = Double(i) / Double(steps)
                    t += 1 / hz
                    samples.append(Trace.Sample(t: t, deg: from + (to - from) * fraction))
                }
            case let .hold(angle, seconds):
                for _ in 0..<max(Int(seconds * hz), 1) {
                    t += 1 / hz
                    samples.append(Trace.Sample(t: t, deg: angle))
                }
            }
        }
        return Trace(name: name, recordedAt: epoch, deviceModel: "synthetic", samples: samples)
    }
}
```

- [ ] **Step 4: Write `TraceReplaySource`**

Create `Sources/LidRippleTrace/TraceReplaySource.swift`:

```swift
import Foundation
import LidRippleCore

/// Replays a trace in real time, honoring the gaps between samples.
///
/// Tests that only need determinism should iterate `trace.angleSamples`
/// directly and skip this entirely; this exists for `lidripple-trace replay`
/// and for driving the app without touching the lid.
public final class TraceReplaySource: LidAngleSource, @unchecked Sendable {
    private let samples: [AngleSample]
    private let speed: Double
    private let queue = DispatchQueue(label: "com.lidripple.replay", qos: .userInteractive)
    private var cancelled = false

    /// - Parameter speed: playback multiplier. 1.0 is real time.
    public init(trace: Trace, speed: Double = 1.0) {
        self.samples = trace.angleSamples
        self.speed = max(speed, 0.01)
    }

    public var isAvailable: Bool { true }

    public func start(_ handler: @escaping @Sendable (AngleSample) -> Void) throws {
        queue.async { [samples, speed, self] in
            let start = DispatchTime.now()
            for sample in samples {
                if lockedIsCancelled() { return }
                let offset = sample.timestamp / speed
                let due = start + .nanoseconds(Int(offset * 1_000_000_000))
                let now = DispatchTime.now()
                if due > now {
                    let waitNanos = due.uptimeNanoseconds - now.uptimeNanoseconds
                    Thread.sleep(forTimeInterval: Double(waitNanos) / 1_000_000_000)
                }
                if lockedIsCancelled() { return }
                handler(sample)
            }
        }
    }

    public func stop() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private let lock = NSLock()
    private func lockedIsCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter TraceReplayTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/LidRippleTrace Tests/LidRippleTraceTests/TraceReplayTests.swift
git commit -m "feat: add trace replay and the six canonical synthetic traces

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Task 10: Trace regression suite and the CLI

This is the M0/M1 deliverable: the driver held to account by every canonical motion, plus the tool that captures real ones.

**Files:**
- Create: `Tests/LidRippleCoreTests/FoldDriverTraceTests.swift`
- Modify: `Sources/lidripple-trace/main.swift` (replace Task 2's temporary probe-only version)
- Create: `docs/traces/README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the `lidripple-trace` CLI with four subcommands — `probe`, `record [--name NAME] [--out PATH]`, `replay PATH [--speed N]`, `info PATH`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LidRippleCoreTests/FoldDriverTraceTests.swift`:

```swift
import Testing
import Foundation
@testable import LidRippleCore
@testable import LidRippleTrace

/// Replays a trace through a driver synchronously and returns every state.
/// Synchronous and deterministic by design: spec section 12 requires fixed
/// timesteps, not wall-clock timing.
private func run(_ trace: Trace, tuning: FoldTuning = .default) -> [FoldState] {
    let driver = FoldDriver(tuning: tuning)
    return trace.angleSamples.map { driver.ingest($0) }
}

@Test func slowCloseReachesFullFoldAndSeals() {
    let states = run(TraceGenerator.slowClose())
    #expect(states.map(\.progress).max()! > 0.99)
    #expect(states.last!.phase == .sealed)
}

@Test func slowCloseIsGraduallyProgressiveRatherThanASnap() {
    let states = run(TraceGenerator.slowClose())
    // The viscous case should spend real time in the visible middle of the fold.
    let midRange = states.filter { $0.progress > 0.2 && $0.progress < 0.8 }
    #expect(midRange.count > 30)      // more than half a second at 60 Hz
}

@Test func slamStaysWithinTheProgressClamp() {
    let states = run(TraceGenerator.slam())
    #expect(states.map(\.progress).max()! <= FoldTuning.default.maxProgress + 1e-9)
    #expect(states.last!.phase == .sealed)
}

@Test func hesitantCloseNeverGoesBackwardsDuringItsPauses() {
    let states = run(TraceGenerator.hesitantClose())
    // Pauses must hold progress, not bleed it away or trigger an unfold.
    #expect(!states.contains { $0.phase == .unfolding })
    #expect(states.last!.phase == .sealed)
}

@Test func stopAndReopenReturnsToIdleWithoutEverCompletingTheFold() {
    let states = run(TraceGenerator.stopAndReopen())
    #expect(states.map(\.progress).max()! < 1.0)
    #expect(states.last!.phase == .idle)
    #expect(states.last!.progress == 0)
}

@Test func wiggleAtRestProducesNoAnimationWhatsoever() {
    let states = run(TraceGenerator.wiggleAtRest())
    #expect(states.allSatisfy { $0.phase == .idle })
    #expect(states.allSatisfy { $0.progress == 0 })
}

@Test func closeReopenCloseEndsSealedWithNoOrphanedState() {
    let states = run(TraceGenerator.closeReopenClose())
    #expect(states.last!.phase == .sealed)
    // It must genuinely pass through idle in the middle, not just unfold partway.
    #expect(states.contains { $0.phase == .idle && $0.progress == 0 })
    #expect(states.contains { $0.phase == .unfolding })
}

@Test func everyCanonicalTraceEndsInATerminalPhase() {
    for trace in TraceGenerator.all {
        let last = run(trace).last!
        #expect(
            [.idle, .sealed].contains(last.phase),
            "\(trace.name) ended mid-transition in \(last.phase)"
        )
    }
}

@Test func progressIsAlwaysInRangeForEveryTrace() {
    for trace in TraceGenerator.all {
        for state in run(trace) {
            #expect(state.progress >= 0, "\(trace.name) went negative")
            #expect(state.progress <= FoldTuning.default.maxProgress + 1e-9, "\(trace.name) overshot")
        }
    }
}

@Test func loweringIntensityDoesNotChangeTimingOrPhases() {
    // Spec FR-17: intensity is a render-only control.
    let full = run(TraceGenerator.slowClose(), tuning: .default)
    let soft = run(TraceGenerator.slowClose(), tuning: FoldTuning.default.withIntensity(0.5))
    #expect(full.map(\.phase) == soft.map(\.phase))
    #expect(zip(full, soft).allSatisfy { abs($0.progress - $1.progress) < 1e-9 })
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FoldDriverTraceTests`
Expected: FAIL. Some tests may pass already; the informative failures are the ones that expose real gaps. Read each failure before changing anything, and fix the driver rather than the assertion unless the assertion is provably wrong.

- [ ] **Step 3: Make the suite pass**

No new production code should be needed — Tasks 4 through 7 implement all of this. If a test fails, the likely causes in order of probability:

1. `hesitantCloseNeverGoesBackwardsDuringItsPauses` fails with a stray `.unfolding` — the direction gate is committing on filter ringing after a ramp ends. Raise `directionMinTravelDegrees`, not the hold time.
2. `closeReopenCloseEndsSealedWithNoOrphanedState` never sees `.idle` — the reopen to 95° is not clearing `idleReturnAngle` long enough for the spring to reach 0. The generator already holds 0.45 s for this reason; if it still fails, confirm `spring.value <= 0.001` is actually reachable rather than lengthening the hold further.
3. `slowCloseIsGraduallyProgressiveRatherThanASnap` fails — feed-forward is overwhelming `u` at 40°/s. Verify the `normalizedRate` sign and magnitude in `publish`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FoldDriverTraceTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Write the full CLI**

Replace `Sources/lidripple-trace/main.swift` entirely. Argument parsing is hand-rolled to keep the package dependency-free (see Global Constraints).

```swift
import Foundation
import LidRippleCore
import LidRippleSensor
import LidRippleTrace

let usage = """
lidripple-trace — lid angle sensor tool

USAGE:
  lidripple-trace probe
  lidripple-trace record [--name NAME] [--out PATH]
  lidripple-trace replay PATH [--speed N]
  lidripple-trace info PATH

  probe    Report whether this Mac has a lid angle sensor, then stream angles.
  record   Stream angles and write a trace JSON on Ctrl-C.
  replay   Replay a trace file through FoldDriver and print fold state.
  info     Summarize a trace file.
"""

func value(for flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func deviceModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var bytes = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &bytes, &size, nil, 0)
    return String(cString: bytes)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(1)
}

switch command {
case "probe":
    let report = SensorProbe.probe()
    print(report.description)
    guard report.isPresent else { exit(0) }
    let source = HIDAngleSource()
    try source.start { sample in
        print(String(format: "%8.2f deg  t=%.3f", sample.degrees, sample.timestamp))
    }
    print("Polling at 60 Hz. Move the lid. Ctrl-C to stop.")
    RunLoop.main.run()

case "record":
    let name = value(for: "--name", in: args) ?? "untitled"
    let out = value(for: "--out", in: args) ?? "\(name).json"
    let source = HIDAngleSource()
    guard source.isAvailable else {
        print("No lid angle sensor on this Mac; nothing to record.")
        exit(1)
    }
    let recorder = TraceRecorder(name: name, deviceModel: deviceModel())

    // Write the trace on Ctrl-C rather than losing it.
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource.setEventHandler {
        source.stop()
        let trace = recorder.finish()
        do {
            try trace.encoded().write(to: URL(fileURLWithPath: out))
            print("\nWrote \(trace.samples.count) samples to \(out)")
            exit(0)
        } catch {
            print("\nFailed to write \(out): \(error)")
            exit(1)
        }
    }
    signalSource.resume()
    signal(SIGINT, SIG_IGN)

    try source.start { recorder.record($0) }
    print("Recording '\(name)' at 60 Hz. Move the lid, then Ctrl-C to save.")
    RunLoop.main.run()

case "replay":
    guard args.count > 1 else { print(usage); exit(1) }
    let trace = try Trace.decoded(from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    let driver = FoldDriver()
    print("phase        progress  angle")
    for sample in trace.angleSamples {
        let state = driver.ingest(sample)
        let phase = state.phase.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)
        print(phase + String(format: "  %7.4f  %6.2f", state.progress, sample.degrees))
    }

case "info":
    guard args.count > 1 else { print(usage); exit(1) }
    let trace = try Trace.decoded(from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    let angles = trace.samples.map(\.deg)
    let duration = (trace.samples.last?.t ?? 0) - (trace.samples.first?.t ?? 0)
    print("""
    name:     \(trace.name)
    device:   \(trace.deviceModel)
    recorded: \(trace.recordedAt)
    samples:  \(trace.samples.count)
    duration: \(String(format: "%.3f", duration)) s
    angles:   \(String(format: "%.2f", angles.min() ?? 0)) to \(String(format: "%.2f", angles.max() ?? 0)) deg
    """)

default:
    print(usage)
    exit(1)
}
```

- [ ] **Step 6: Verify the CLI manually**

```bash
swift build
swift run lidripple-trace                          # prints usage
swift run lidripple-trace probe                    # streams angles (sensor Macs)
swift run lidripple-trace record --name slow-close --out /tmp/slow-close.json
swift run lidripple-trace info /tmp/slow-close.json
swift run lidripple-trace replay /tmp/slow-close.json | head -40
```

Expected on a sensor-equipped Mac: `record` writes a file on Ctrl-C; `info` reports a plausible duration and angle range; `replay` shows the phase marching `idle → armed → folding → sealed` with progress rising smoothly to ~1.0.

On a sensor-less Mac, `record` exits cleanly with the explanatory message, and `replay`/`info` still work on any committed trace.

- [ ] **Step 7: Document the trace workflow**

Create `docs/traces/README.md`:

```markdown
# Lid traces

A trace is a recorded sequence of real lid angles. Traces are how the fold
animation gets tested without closing a laptop hundreds of times (spec §12).

## Recording one

```bash
swift run lidripple-trace record --name slow-close --out docs/traces/slow-close.json
```

Move the lid, then Ctrl-C to save.

## Inspecting one

```bash
swift run lidripple-trace info docs/traces/slow-close.json
swift run lidripple-trace replay docs/traces/slow-close.json
```

`replay` prints the phase and progress `FoldDriver` produces for each sample —
the fastest way to see why a motion behaves the way it does.

## Synthetic vs recorded

`TraceGenerator` builds the six canonical motions deterministically, so the test
suite runs identically on any machine, including one with no lid sensor. Real
recordings are committed here as extra fixtures during M4, when the animation is
tuned against genuine hand motion.
```

- [ ] **Step 8: Run the full suite**

Run: `swift test`
Expected: PASS, all tests across both test targets.

- [ ] **Step 9: Commit**

```bash
git add Tests/LidRippleCoreTests/FoldDriverTraceTests.swift Sources/lidripple-trace/main.swift docs/traces/README.md
git commit -m "feat: add trace regression suite and the lidripple-trace CLI

Completes M0 and M1: the driver is now held to account by all six canonical
lid motions, and real traces can be recorded, inspected, and replayed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014ZkYSqsoJK5Y2mcxGKj1mq"
```

---

## Definition of done

- [ ] `swift build` and `swift test` both pass from the repo root.
- [ ] `swift run lidripple-trace probe` streams plausible angles on a sensor-equipped Mac.
- [ ] Task 2 Step 6 confirmed **no Input Monitoring permission is required** — spec §15's top risk is retired, or the finding is reported.
- [ ] The raw-to-degrees scale factor is empirically verified and recorded in spec §4.
- [ ] `FoldDriver` and everything it touches import only `Foundation`.
- [ ] No constant appears outside `FoldTuning`.
- [ ] All six canonical traces pass their regression tests.
- [ ] No Metal, ScreenCaptureKit, AppKit, or app bundle exists yet — that is Plan 2.

## What Plan 2 covers (M2)

Overlay window at `CGShieldingWindowLevel()`, ScreenCaptureKit freeze-frame with the speculative warm band, the six-stage Metal fold shader, golden-image tests, and the scrub/preview mode. It depends on this plan's `FoldDriver` and `FoldTuning` and nothing else, which is exactly why the boundary is here.
