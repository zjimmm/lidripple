# lidripple Plan M3: Runtime Integration

**Goal:** Wire the real lid sensor through `FoldDriver`, speculative
`CaptureCoordinator`, `OverlayPresenter`, and `FoldMetalView` so closing, live reversal,
sleep/lock, and fresh post-unlock unfold paths behave as one re-entrant runtime.

**Scope:** M3 owns integration and every lifecycle case in PRD §10. It does not ship the
final product surface. M5 still owns `EventAngleSource`, the complete menu bar,
permission onboarding, login item, app bundle/signing/notarization, README, cask,
license, and Sponsors link. M3 must nevertheless make sensor loss observable and expose
a tested recovery/fallback handoff so M5 can attach `EventAngleSource` without changing
the capture/renderer state machine.

**Architecture:** Add a `LidRippleIntegration` library between I/O adapters and the thin
app executable. A main-actor `FoldRuntime` owns one `FoldDriver` cycle and coordinates
injected capture/presentation protocols. It consumes ordered samples and explicit
lifecycle events, publishes diagnostic state, and uses generation tokens to discard
late async warm/freeze results. `AppDelegate` owns macOS notifications, the physical
`HIDAngleSource`, one runtime, and one display-target provider. Sensor recovery is a
separate policy with injected clock/scheduler behavior and a terminal
`fallbackRequired` result; it never constructs M5's fallback source.

**Constraints:** Swift 6, macOS 14+, no third-party or network dependency; no captured
content on disk or in logs. `LidRippleCore` remains pure. All AppKit-facing work stays on
the main actor, capture teardown is awaited, and there is at most one owned overlay,
capture cycle, scripted-unfold timer, and sensor retry sequence.

## Implementation record

Implemented on `feature/m3-integration`. The shipped names are
`FoldLifecycleCoordinator`, `FoldLifecycleProtocols`, `FoldRuntimeDiagnostics`, and
`SensorRecovery` (the plan's earlier shorthand `FoldRuntime` was not retained). Runtime
authority is modeled orthogonally: enablement, console-session restriction, built-in
display presence, and sensor health cannot overwrite one another. `AppDelegate` uses a
source-generation token as the input replacement seam, so samples queued by a stopped
HID source are discarded before they reach the driver.

All automated tasks below are implemented. The physical/manual portion is recorded
honestly in `docs/verification/2026-09-12-m3-manual-matrix.md`; unchecked physical rows
are pre-release acceptance work, not automated claims.

## Requirement traceability

| Requirement | Code evidence | Automated evidence | Manual evidence |
|---|---|---|---|
| FR-1 | `FoldRuntime` keeps capture idle and presentation hidden/paused in `idle` | idle and return-to-idle resource tests | Activity Monitor/GPU HUD with open static lid |
| FR-2 | `.armed` starts one 10 fps warm stream and draws nothing | ordered transition and duplicate-arm tests | slow physical close through 110° |
| FR-3 | first `.folding` freezes newest frame, stops stream, installs it, then presents | fake capture event-order test; no-frame failure test | close through 75° with Screen Recording granted |
| FR-4 | every active sample/tick forwards the driver's spring state to the presenter | progress-forwarding and trace integration tests | compare overlay against logged angle during close |
| FR-5 | `<12°`/sleep reaches sealed; sleep immediately invalidates and tears down capture | sealed and sleep-race tests | close fully and sleep during fold |
| FR-6 | opening samples drive `.unfolding` through the same driver/source texture | reversal trace integration test | reopen at 25%, 50%, and 90% |
| FR-7 | settled progress 0 above 78° hides, clears, resets capture, returns idle | cleanup/hysteresis test | reopen fully after partial close |
| FR-8 | generation ownership prevents pop, stale install, double capture, or progress 1 on reversal | close-reopen and close-reopen-close trace tests | repeated reversal stress run |
| FR-9 | lock/session-inactive events suppress output and route the cycle to locked/sealed bookkeeping | lock-before/during-fold tests | close while locked; fast user switch |
| FR-10 | unlock captures a fresh frame with bounded first-frame wait, then starts the 620 ms curve; capture failure uses a non-stale dark reveal | fresh-generation, ordering, 620 ms, and failure-path tests | lock, mutate desktop, unlock; deny capture variant |
| FR-13 | target comes only from `BuiltInDisplay`; its ID is supplied to capture and its screen to the one overlay | external IDs are rejected/never forwarded | built-in + external display check |
| FR-14 | clamshell does not use sleep as the close trigger; sensor samples continue to drive built-in fold/reversal | no-sleep close/reopen integration test | external display attached, clamshell close/open |

FR-11/FR-12 are M5 deliverables. M3 supplies `SensorRecoveryOutcome.fallbackRequired`
and a runtime method for atomically replacing the input source; M5 supplies the timed
driver and surfaces the selected mode in its menu.

## §10 lifecycle traceability

| §10 case | Required M3 behavior | Verification |
|---|---|---|
| 1. Sleep race | hard seal, invalidate pending work, stop capture immediately | async stop-order test + manual sleep mid-fold |
| 2. Display blanking | preserve the driver's 25° completion; no late capture dependency | canonical close trace + full-close manual check |
| 3. Clamshell | affect built-in only and retain angle-tracked reopen without sleep | dual-display fake IDs + clamshell manual check |
| 4. Lock screen | never order overlay above loginwindow; unlock uses fresh capture | presenter-spy ordering test + locked manual run |
| 5. Fullscreen/Spaces | preserve the existing shielding window contract | existing overlay assertions + fullscreen manual run |
| 6. Self-capture | pass the sole overlay `windowID` on every warm/cold capture | exact-argument tests + ScreenCaptureKit smoke |
| 7. DRM | accept and render a black captured texture without inspection/special case | black-frame integration test + document for M5 README |
| 8. Re-entrancy | generation-token stale-result rejection; idempotent capture/window ownership | delayed-fake close-reopen-close test |
| 9. Display reconfiguration | observe screen changes; resize if same built-in remains, otherwise abort sealed and teardown | target-change tests + attach/detach manual run |
| 10. Fast user switching | cancel work, hide/clear, reset driver/capture to idle | session-resign test + manual user-switch check |
| 11. Thermal/low power | renderer quality policy removes auxiliary blur taps while retaining frame cadence | quality-toggle tests + thermal/low-power notification smoke |
| 12. Sensor disappears | bounded exponential reopen attempts, then one fallback handoff | deterministic retry/backoff test + unplug/wake-equivalent fault injection |

## Planned files

| File | Responsibility |
|---|---|
| `Package.swift` | Add integration library and tests; make app depend on it and Capture |
| `Sources/LidRippleIntegration/FoldLifecycleCoordinator.swift` | Ordered phase/capture/presentation orchestration |
| `Sources/LidRippleIntegration/FoldLifecycleProtocols.swift` | Narrow capture, presenter, and display seams |
| `Sources/LidRippleIntegration/SensorRecovery.swift` | Backoff policy and fallback-required handoff |
| `Sources/LidRippleIntegration/FoldRuntimeDiagnostics.swift` | Public pixel-free mode/resource state for M5 UI and tests |
| `Sources/LidRippleCapture/CaptureCoordinator.swift` | Bounded first-frame wait needed by fresh unlock capture |
| `Sources/LidRippleOverlay/OverlayPresenter.swift` | Explicit hide, safe resize, fallback reveal, quality forwarding |
| `Sources/LidRippleRenderer/FoldMetalView.swift` and renderer uniforms/shader | Reduced-tap mode and dark-to-transparent fallback presentation |
| `Sources/LidRippleApp/AppDelegate.swift` | Source wiring and macOS sleep/lock/session/display/power notifications |
| `Tests/LidRippleIntegrationTests/*` | Deterministic orchestration, races, traces, recovery, and policy tests |

## Task 1: Integration seams and ownership model

- [ ] Add `LidRippleIntegration`/tests and protocol adapters for capture and presentation.
- [ ] Define `RuntimeDiagnostics` with phase, capture activity, overlay visibility,
      lock/session state, input health, and reduced-quality status; never include pixels.
- [ ] Implement one-cycle/generation ownership and a serialized sample entry point.
- [ ] Prove idle has no active capture/draw, duplicate events are idempotent, and late
      fake completions cannot mutate a newer cycle.
- [ ] Run the full suite and commit.

## Task 2: Physical close and live reopen

- [ ] On first `.armed`, warm the built-in display at 10 fps while excluding the owned
      overlay window; do not show or draw.
- [ ] On first `.folding`, await warm startup, freeze the newest complete frame, stop the
      stream, install the frame, and only then present the latest active state.
- [ ] Forward active driver states/ticks at display cadence; reuse the immutable frame
      through folding/unfolding and clear it only after clean idle/sealed teardown.
- [ ] Cover slow close, slam, hesitant close, stop-and-reopen, rest wiggle, and
      close-reopen-close using the checked-in trace corpus plus delayed capture fakes.
- [ ] Assert FR-1–8 ordering, hysteresis, no double capture/window, and no stale installs.

## Task 3: Sleep, lock, and post-unlock reveal

- [ ] Make sleep a hard synchronous driver seal plus async generation-invalidating
      capture reset; cancel any scripted unfold.
- [ ] Track console-session/lock state using both the initial CGSession dictionary and
      lock/unlock notifications. While locked, hide the overlay and ignore physical-open
      presentation even if sensor samples continue.
- [ ] On unlock, discard old content, warm the built-in capture, wait a bounded interval
      for its first complete frame, freeze/stop, then begin the 620 ms scripted unfold.
- [ ] If fresh capture fails, install no prior texture and run a warm-black-to-transparent
      reveal over the identical 620 ms timing before returning idle.
- [ ] Test lock at every active phase, sleep/freeze races, stale-frame rejection, exact
      operation ordering, failure reveal, and completion cleanup.

## Task 4: Display, session, and rendering-pressure events

- [ ] Observe `didChangeScreenParametersNotification`. Resize against the current
      built-in panel when identity is stable; otherwise seal, hide, and tear down.
- [ ] On workspace session resignation/fast-user-switch, cancel all work and return
      driver, overlay, and capture to idle. A later active session begins cleanly.
- [ ] Add an explicit normal/reduced render-quality mode. Thermal serious/critical or
      low-power mode disables auxiliary blur taps but does not reduce the update cadence;
      nominal state restores them.
- [ ] Test display identity/frame changes, session switching, and quality transitions;
      preserve the existing fullscreen/Spaces window tests.

## Task 5: Sensor recovery and M5 fallback handoff

- [ ] Add `SensorRecovery` with deterministic exponential delays (bounded attempt count
      and maximum delay), cancellation on shutdown/source replacement, and exactly one
      terminal `fallbackRequired` result.
- [ ] On wake or a sensor read/service failure, stop the old HID source, reset runtime
      resources safely, and ask an injected factory to reopen it.
- [ ] Expose the equivalent input handoff needed by M5: generation-gated `ingest`,
      `sensorUnavailable()` / `sensorRecovered()`, and pixel-free diagnostics. M5 will
      generalize AppDelegate's stored source to `any LidAngleSource` when it binds
      `EventAngleSource`; do not implement that source or its menu indicator here.
- [ ] Test success on each retry, exhaustion, cancellation, duplicate wake events, and
      preservation of ordered samples after replacement.

## Task 6: Thin app wiring and end-to-end gates

- [ ] Replace direct sensor-to-overlay calls in `AppDelegate` with one `FoldRuntime`;
      create exactly one overlay/capture pair for the built-in display.
- [ ] Register and remove sleep/wake, lock/unlock, session active/inactive,
      display-change, thermal, and power-state observers. Make termination await/reset
      capture and stop the sensor without orphaning a timer or window.
- [ ] Keep only the existing development Quit menu. Do not pre-empt M5 menu,
      onboarding, launch-at-login, or packaging work.
- [ ] Run `swift test -Xswiftc -warnings-as-errors` and a release build with warnings as
      errors. Run opt-in ScreenCaptureKit and renderer smoke checks on supported hardware.
- [ ] Manually exercise: unlocked close/open, reversal at three points, full close/sleep,
      lock/unlock with desktop changed, capture denial fallback reveal, fullscreen Space,
      clamshell with external display, display attach/detach mid-fold, fast user switch,
      low-power toggle, and sensor-recovery fault injection. Record unavailable hardware
      combinations honestly rather than marking them passed.
- [ ] Perform whole-milestone review, fix Critical/Important findings, rerun all gates,
      then merge M3 to `main`, commit, and push as the milestone boundary.

## Definition of done

- [ ] FR-1–10 and FR-13–14 have the code/test/manual evidence listed above.
- [ ] Every §10 edge case is implemented; manual-only gaps are explicitly recorded.
- [ ] Idle owns no stream and schedules no Metal work; every terminal/error path tears
      down capture and hides or safely holds exactly one overlay.
- [ ] Fresh unlock content can never alias a pre-lock capture; capture failure never
      reveals stale user content.
- [ ] Re-entrant async completions cannot install a frame or show a window for an
      obsolete cycle.
- [ ] M5 can attach fallback input and read runtime mode/permission/health without
      rewriting integration state.
- [ ] Full debug tests, warnings-as-errors tests/build, relevant smoke checks, and the
      recorded manual matrix are green or truthfully marked unavailable.
