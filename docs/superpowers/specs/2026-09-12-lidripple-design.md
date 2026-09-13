# lidripple — Product Requirements & Design

**Status:** Approved design, ready for implementation planning
**Date:** 2026-09-12
**Owner:** Jim
**Type:** New project (macOS app, open source)

---

## 1. Summary

lidripple is a macOS background agent that plays Apple's iPhone Duo fold transition on a
MacBook's built-in display, driven in real time by the physical lid angle.

On iPhone Duo, opening or closing the device does not cut between the outer and inner
display the way other foldables do. The interface bends in perspective around the hinge
and progressively blurs — strongest at the fold — before dissolving into darkness. The
effect is widely regarded as the standout piece of Apple's foldable software design.

A MacBook lid is also a hinge. lidripple reads the hidden lid angle sensor at 60 Hz and
folds a frozen capture of the screen into the keyboard hinge as you close the laptop,
reversing live if you change your mind mid-close.

The product is the animation. Every other decision in this document serves its fidelity.

---

## 2. Motivation

Three things make this worth building:

1. **The effect is genuinely beautiful and genuinely transferable.** The Duo animation is
   about a hinge consuming pixels. MacBooks have a hinge and, on most recent models, a
   sensor that reports its angle to 0.01°. The mapping is natural rather than forced.
2. **The physical coupling is the point.** An animation that tracks your hand — that slows
   when you slow, reverses when you hesitate — is a categorically different experience
   from a timed animation triggered by an event. This is what makes it feel like the Mac
   is a physical object rather than a computer playing a video.
3. **Existing implementations leave fidelity on the table.** See §4.

---

## 3. Goals and non-goals

### 3.1 Goals

- G1. Fold the built-in display's contents into the hinge as the lid closes, tracking the
  real lid angle, at full display refresh and native resolution.
- G2. Reverse live and smoothly if the lid is reopened mid-close.
- G3. Play an opening animation after physical reopen or unlock when the active session,
  built-in display, and Screen Recording permission allow a fresh frame. Never draw
  above `loginwindow` or replay a stale pre-sleep frame.
- G4. On Macs without a validated lid angle sensor, fail safely at sleep and provide a
  fresh scripted unfold after unlock when session and Screen Recording conditions allow
  it. A close animation may play only when an early public trigger and a visible panel
  window have been demonstrated; it is not guaranteed in v1.
- G5. Visibly exceed existing implementations on animation quality, judged by a
  frame-matched side-by-side against real iPhone Duo footage.
- G6. Cost nothing when idle: no capture stream, no GPU work, negligible CPU.
- G7. Be trustworthy as an open-source app that captures the screen: minimum permissions,
  clearly explained, nothing hidden.

### 3.2 Non-goals (v1)

Deliberately excluded, each because it trades fidelity or trust for breadth:

- N1. Folding external displays. The effect represents *that physical panel* closing.
- N2. Multiple effect presets (ripple, page curl, CRT collapse). The project name hints
  at a plugin architecture; v1 ships one effect, done extremely well.
- N3. Lock screen rendering. Requires disabling SIP. Not acceptable.
- N4. Intel optimization beyond "it runs."
- N5. Mac App Store distribution. Impossible; see §11.
- N6. Any preferences beyond enable/disable, intensity, launch-at-login, and the debug
  scrubber.
- N7. Sparkle or any auto-update framework. GitHub releases plus a "check for updates"
  link is sufficient at this scale.

---

## 4. Prior art and differentiation

**`lqSky7/iphone-duo-macos-animation` (macTilt)** is the existing open-source
implementation. It reads the same HID sensor, uses ScreenCaptureKit plus Metal, and folds
the display from top to bottom toward the hinge with progressive blur. It establishes the
approach and validated that the sensor path works.

lidripple differentiates on four specific axes:

| Axis | macTilt | lidripple |
|---|---|---|
| Motion model | Angle mapped directly to progress | Angle as spring *target*, with velocity feed-forward — viscous on slow closes, continuous through reversal, immune to sensor jitter |
| Fold geometry | 3D fold toward the hinge | Non-rigid squash: upper rows crowd into the hinge non-uniformly, so pixels are *consumed* rather than rotated |
| Blur curve | Progressive blur | Blur arrives late (`p²`), so early motion stays crisp — a large part of why the real effect reads as expensive |
| Testability | Manual | Trace record/replay plus golden-image shader tests; the feel is a pure, unit-tested function |

**Hardware reference** (from `samhenrigold/LidAngleSensor`, `tcsenpai/pybooklid`, and
macTilt): Apple internal lid angle sensor, `IOHIDDevice` VID `0x05AC`, PID `0x8104`,
usage page `0x0020` (sensor), usage `0x008A` (orientation), read via a Feature report
(report ID 1, 8-byte buffer, little-endian UInt16 at bytes 1–2), polled at 60 Hz.

The raw-to-degrees scale was originally assumed to be 0.01° precision (a 16-bit value
scaled down), matching the reference implementations' stated fidelity. Task 2's hardware
investigation on this plan's test machine (Mac16,12) found evidence against that: with
the lid physically open (`ioreg -r -k AppleClamshellState` reporting
`AppleClamshellState = No`), the sensor steadily reported raw value `0x0063` = 99 over
300 samples. An open lid cannot be at 0.99°, which rules out the 0.01° scale and
corroborates the unscaled mapping actually shipped in
`Sources/LidRippleSensor/HIDAngleSource.swift` (`rawToDegrees = 1.0`, i.e. 1 LSB = 1°,
whole degrees reported directly). See `docs/sensor.md` for the full write-up.

This is corroboration, not confirmation: it has NOT been verified by a full physical
sweep across known angles (closed, and several angles in between). That sweep still
requires a human's hands and is outstanding work for whoever picks up sensor tuning
next.

---

## 5. Users

- **Primary:** MacBook owners who care about interface craft — the audience that made the
  Duo animation go viral. They will install it, close the lid, show a friend, and leave a
  GitHub star. Success with this group is entirely about the first five seconds.
- **Secondary:** Mac and graphics developers reading the source for the sensor integration
  and the Metal fold shader. Success with this group is a legible architecture and a
  README that explains the math.

---

## 6. Hardware and OS requirements

- **macOS 14.0 or later.** ScreenCaptureKit is mature here and the HID and display APIs
  needed are all present.
- **Apple Silicon or Intel MacBook.** Apple Silicon is the tuning target.
- **Lid angle sensor: strongly preferred, not required.** Broadly present on MacBook Pro
  models from 2019 onward. Notably absent or non-reporting on several M1/M2 MacBook Air
  and 13-inch MacBook Pro configurations. The app detects this at launch and switches
  drivers (§7.4) rather than failing.
- **Screen Recording permission.** Required; see §11.

---

## 7. Functional requirements

### 7.1 Closing (primary path, sensor present)

- FR-1. While the lid is open and static, the app performs no capture and no rendering.
- FR-2. When the angle drops below 110° with closing velocity (θ̇ < −5°/s, using the same
  threshold as §9.2 so arming cannot chatter), the app enters `armed`: a
  low-frame-rate ScreenCaptureKit stream warms up. Nothing is drawn.
- FR-3. When the angle drops below 75°, the app freezes on the newest captured frame,
  stops the stream, presents the overlay, and begins the fold.
- FR-4. Fold progress follows the spring model in §9.1; the fold is visually complete by
  25°, before the panel becomes unviewable at a glancing angle.
- FR-5. Below 12°, or on a system sleep notification, the app enters `sealed` and holds
  the final near-black frame until teardown.

### 7.2 Reopening while unlocked (angle-tracked)

- FR-6. Sustained opening velocity above 5°/s for 50 ms transitions `folding` to
  `unfolding`; progress runs backward under the same spring, so the image climbs back out
  of the hinge as the lid rises.
- FR-7. Reaching progress 0 with the angle above 78° dismisses the overlay and returns to
  `idle`. The 3° gap against the 75° entry threshold is deliberate hysteresis.
- FR-8. Reversal at any progress must return to a clean idle state with no visual pop and
  without progress ever reaching 1.0 on the way.

### 7.3 Reopening after lock (scripted unfold)

- FR-9. If the session locked, the app must not attempt to draw during the physical
  opening; macOS does not permit drawing above `loginwindow`, and trying produces a
  visible failure. Lock state is detected via `kCGSSessionOnConsoleKey` and the
  `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` notifications.
- FR-10. On successful unlock, when the active session, built-in display, and Screen
  Recording permission allow capture, the app captures a **fresh** frame and unfolds it
  from progress 1 to 0 over 620 ms on a spring-shaped curve. If those conditions are
  absent, it stays sealed without drawing. Unfolding the pre-sleep capture would be an
  obvious tell; the user must see the desktop as it is now.

### 7.4 Sensor-less Macs (limited mode)

- FR-11. At launch, probe for the HID sensor. If absent or lost after bounded recovery,
  select sensor-less mode with the same `FoldDriver`, capture, overlay, renderer, and
  tuning. Its synthetic source owns no active timer while waiting. A ~550 ms close may
  run only if a supported public trigger is measured to arrive while the built-in panel
  can still show the program. Otherwise `willSleep` immediately seals and tears down
  capture without a visible close. Do not delay forced sleep, use an undocumented
  production trigger, or draw over `loginwindow`. After unlock, use the normal fresh-frame
  scripted unfold when the session, display, and Screen Recording permission allow it.
- FR-12. The menu and README identify sensor-less mode as limited/experimental until
  physically qualified. They state that close animation may be absent, angle tracking
  and mid-close reversal are unavailable, and a no-sleep clamshell close may be
  undetectable. A unit-tested 550 ms source alone must not be advertised as a visible
  close on real hardware.

### 7.5 Displays

- FR-13. The fold plays only on the built-in display. External displays are never
  captured and never overlaid.
- FR-14. In clamshell mode with an external display attached, a sensor-equipped Mac may
  remain awake, so its built-in fold can play on close and reopen stays angle-tracked.
  This is the best-case demonstration path. Without a validated sensor, a no-sleep
  clamshell close may be undetectable and must not be advertised as angle-tracked.

### 7.6 Application surface

- FR-15. `LSUIElement` agent: menu bar item only, no Dock icon, no window in normal use.
- FR-16. Menu bar exposes enable/disable, intensity, launch-at-login, active input mode,
  permission state, and the debug scrubber.
- FR-17. **Intensity** is a single 0.5–1.0 multiplier applied to exactly three `FoldTuning`
  terms: blur radius, rotation angle, and squash exponent. It never alters timing,
  thresholds, or the spring, so reducing intensity softens the effect without changing how
  it tracks the lid. Default 1.0.

---

## 8. Architecture

All of the product's *feel* lives in one pure, synchronous module with no I/O and no
Metal. Angle samples in, fold state out. The hardest things to get right — momentum,
reversal, hysteresis — therefore become unit-testable and replayable from recorded
traces, instead of debugging by closing a laptop four hundred times.

```
 IOHIDDevice 0x05AC/0x8104        supported optional event
 usage 0x0020:0x008A @60Hz        + wake/unlock events
          |                                |
   HIDAngleSource                   EventAngleSource     <- both conform to
          \                                /                LidAngleSource
           +--------------+---------------+
                          v
                AngleSample{deg, t}
                          v
          +-------------------------------+
          |   FoldDriver   (PURE)         |   no I/O, no Metal,
          |   state machine + spring      |   fully unit-testable
          +-------------------------------+
                          v
        FoldState{phase, progress 0..1, velocity}
                          |
        +-----------------+------------------+
        v                                    v
  CaptureCoordinator                  OverlayPresenter
  (SCStream warm/freeze/stop)         (shielding NSWindow,
        |                              built-in screen only)
        |  MTLTexture (frozen frame)          |
        +------------------+------------------+
                           v
                     FoldRenderer
              (Metal: mesh warp -> mip blur
               -> void horizon -> rim light)
```

### 8.1 Modules

| Unit | Responsibility | Depends on |
|---|---|---|
| `LidAngleSource` | Protocol: a stream of `AngleSample`. The seam for fakes and trace replay. | — |
| `HIDAngleSource` | Opens the HID device, polls at 60 Hz, emits samples, reports `isAvailable`. | IOKit |
| `EventAngleSource` | Sensor-less source: timed angle ramp only after a qualified visible-close trigger; otherwise idle until fresh unlock handling. | App-provided events |
| `FoldDriver` | **Pure.** Phase machine, spring integrator, hysteresis. The product's feel. | nothing |
| `CaptureCoordinator` | Warms, freezes, and stops the stream on phase changes; maintains the content filter. | ScreenCaptureKit |
| `FoldRenderer` | Texture plus `FoldState` to one rendered frame. Stateless per frame. | Metal |
| `OverlayPresenter` | Window lifecycle at `CGShieldingWindowLevel()`, built-in display only. | AppKit |
| `AppCoordinator` | Menu bar, permission onboarding, mode indicator, debug scrubber. | all |

Each unit answers the three questions cleanly: what it does, how you use it, what it
depends on. `FoldDriver` depending on nothing is the load-bearing property of the design.

### 8.2 Phase machine

```
idle --(θ<110°, closing)--> armed --(θ<75°)--> folding
                                                 |  ^
                                    (opening)    v  |  (closing)
                                              unfolding
folding --(θ<12° | willSleep)--> sealed
unfolding --(p==0 && θ>78°)--> idle
sealed --(screenIsUnlocked)--> scripted unfold --> idle
```

### 8.3 Capture strategy

**Freeze-frame with speculative warm-up.** A low-frame-rate `SCStream` spins up only
inside the sensitive band (110°→75°, closing). At fold start the newest frame is frozen
into an `MTLTexture` and the stream is stopped; the shader works from that one static
texture for the whole fold.

This is chosen over a live continuous stream for three reasons: iPhone Duo itself freezes
the UI mid-fold, so it is the faithful behavior; it is several times cheaper at exactly
the moment the system is busiest; and the warm-up removes the 30–60 ms capture hitch that
a cold one-shot grab would place on frame one, where a hitch is most visible.

Private window-server transforms (CGSPrivate/SkyLight, as the Dock's genie effect uses)
were considered and rejected: private API that breaks across macOS releases, may require
SIP disabled, and is indefensible in an open-source app that users are trusting with
screen access.

---

## 9. Animation specification

### 9.1 Angle to progress

MacBook lids travel roughly 0–135°. The fold maps to a window inside that:

```
u = clamp((75° − θ) / (75° − 25°), 0, 1)
```

It completes by 25° because past roughly 20° the panel cannot be seen at a glancing
angle; finishing later means finishing invisibly.

`u` is the *target*, never the output. A second-order spring chases it:

- stiffness `k ≈ 220`, damping `c ≈ 26` (ζ ≈ 0.88, slight overshoot on fast input)
- integrated at a fixed 1/240 s substep for stability regardless of sample jitter
- feed-forward term `α·θ̇` with `α ≈ 0.06`, so fast closes lead slightly
- output clamped to `[0, 1.06]`; the renderer reads values above 1 as extra void

The spring buys three things at once: slow closes feel viscous rather than mechanical,
reversal flows instead of snapping direction, and sensor jitter is absorbed rather than
displayed.

### 9.2 Noise handling

0.01° precision at 60 Hz is precise, not clean.

- one-pole prefilter on raw angle, cutoff ~15 Hz
- ±0.3° deadband around the last committed angle
- direction changes require `|θ̇| > 5°/s` sustained for 50 ms, so a hand resting on the
  lid cannot strobe the effect
- phase entry at 75°, exit at 78°

### 9.3 Render stages

Driven by progress `p` and source row `v` (0 at the hinge/bottom, 1 at the top).

1. **Non-rigid squash.** 16×64 tessellated mesh. `v' = pow(v, 1 + 1.8p)` crowds upper
   rows toward the hinge far harder than lower ones. This non-uniformity is the
   "drawn into the hinge" signature and the core visual differentiator.
2. **Perspective.** Rotate the mesh about the hinge axis by `p · 72°` through a
   short-focal projection (fov ≈ 38°, eye ≈ 1.1 screen-heights back, slightly above).
   Horizontal narrowing of receding rows falls out of the projection for free; that
   narrowing is what reads as 3D rather than as a vertical scale.
3. **Progressive blur.** A 6-level mip chain built by separable Gaussian downsample
   **once per capture, not per frame**. Per fragment,
   `r = p² · (0.15 + 1.85·v^1.4) · 28px`, converted to a fractional mip LOD and sampled
   trilinearly with one extra tap to hide banding. The `p²` makes blur arrive late, so
   early motion stays crisp — a large part of why the real effect feels expensive.
4. **Void horizon.** `smoothstep((v − 1.15p) / 0.28)` climbs a dark line up the image,
   consuming rows as `p → 1`. Blend toward a faint warm-black, never pure `#000`: pure
   black reads as a dead pixel region instead of depth.
5. **Rim light.** A narrow specular band riding the horizon,
   `exp(−((v − 1.15p) / 0.012)²)`, cool-tinted, additive at ~0.35, widening with `p`.
   Plus a whole-frame cool tint ramp and a subtle vignette. This is the layer that reads
   as glass folding rather than a texture fading.
6. **Blue-noise dither** at 1.5/255 before output. Not optional: stages 4 and 5 are large
   smooth dark gradients and will band visibly on an 8-bit path.

Rendered at native backing scale into the overlay's `CAMetalLayer`, vsync on, triple
buffered.

### 9.4 Tuning

All ~12 constants live in one `FoldTuning` struct — thresholds, `k`, `c`, `α`, the 1.8
squash exponent, 72° rotation, 28 px blur radius, the `p²` exponent, 1.15 void speed, rim
width. The struct is `Codable` and hot-reloadable from a JSON override file while
scrubbing. Tuning is a data change, not a rebuild. This is what makes converging on the
real animation's feel tractable.

---

## 10. Lifecycle and edge cases

The twelve cases that decide whether the app feels finished rather than like a demo:

1. **Sleep race.** macOS may sleep before the fold finishes. `NSWorkspace.willSleepNotification`
   is a hard jump to `sealed` plus immediate capture teardown. Carrying a stream across
   sleep yields an invalid stream on wake.
2. **Display blanking.** The panel blanks near full close; nothing to do but finish before
   it, which is why `θ_end = 25°`.
3. **Clamshell mode.** External display attached means no sleep: fold the built-in, leave
   externals alone, and the reopen stays angle-tracked.
4. **Lock screen.** Cannot draw above `loginwindow`. Detect and route to the scripted
   unfold (FR-9, FR-10) rather than attempting and failing.
5. **Fullscreen apps and Spaces.** `CGShieldingWindowLevel()` with
   `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`, `ignoresMouseEvents`.
6. **Self-capture recursion.** Always exclude the overlay window from `SCContentFilter`.
   Freeze-frame mostly avoids this, but the warm stream and the reversal case overlap.
7. **DRM and protected content.** ScreenCaptureKit returns black for it. Fold the black
   frame; document the behavior; do not special-case it.
8. **Re-entrancy.** Close to 40°, reopen to 90°, close again must never double-capture or
   orphan a window. One owned window instance; the capture coordinator is idempotent.
9. **Display reconfiguration mid-fold.** Observe `didChangeScreenParametersNotification`;
   if the built-in screen's frame changes, resize or abort to `sealed`.
10. **Fast user switching.** Bail to `idle`.
11. **Thermal or low-power throttling.** Degrade blur tap count rather than drop frames.
12. **Sensor service disappearing on wake.** Reopen with backoff; fall back to event mode
    if it stays absent.

---

## 11. Permissions, privacy, and security

- **Screen Recording (TCC) is required** for ScreenCaptureKit. First run explains why in
  plain language *before* triggering the system prompt. Denial degrades to a menu-bar
  "needs permission" state with a deep link to the right Settings pane — never a silent
  no-op.
- **No Accessibility permission. No Input Monitoring.** Stated prominently in the README;
  for an open-source app that captures the screen, the permission list is the trust story.
- **Captured frames never leave the GPU.** No disk writes, no network, no telemetry, no
  analytics. The app makes zero outbound connections.
- **Capture duration is seconds per day**, only inside the sensitive lid band.
- **App Sandbox is off.** Non-standard HID device access plus capture-filter exclusion make
  it impractical. This is the direct reason lidripple ships as a notarized Developer ID
  DMG and not a Mac App Store app (N5).
- **Risk to verify in week one:** some macOS versions gate `IOHIDDeviceOpen` behind Input
  Monitoring depending on usage page. Sensor page `0x0020` should not be affected, but
  confirm before building on the assumption. If it is gated, the permission story in the
  README changes materially.

---

## 12. Testing strategy

A lid cannot be closed four hundred times by hand. The test infrastructure is therefore
part of the product, and one piece of it comes first.

1. **Trace record/replay — build this before the shader.** A record mode dumps real
   `(t, θ)` samples to JSON. Tests replay canned traces at fixed timesteps,
   deterministically: slow close, slam, hesitant close, stop-at-45-then-reopen,
   wiggle-at-rest, close-reopen-close. This is the highest-value infrastructure in the
   project.
2. **`FoldDriver` unit tests.** Reversal never crosses 1.0; rest jitter causes no phase
   change; a slam overshoots at most 1.06 and settles; every phase transition fires on the
   documented threshold with hysteresis respected.
3. **Golden-image shader tests.** Render a known checkerboard-plus-gradient input
   offscreen at `p` = 0, 0.25, 0.5, 0.75, 1.0; compare against reference PNGs at roughly
   2/255 per-pixel tolerance and fail on mean-error regression. Catches shader math drift
   during tuning.
4. **Scrub/preview mode.** Menu item plus hotkey: show the overlay with a manual progress
   slider and a synthetic angle-ramp player. Used constantly during development, and it
   doubles as the README GIF rig.
5. **Performance assertions.** Frame time under 4 ms at 3456×2234 on an M1 Pro, logged and
   asserted in debug builds.
6. **Manual matrix** (the irreducible part for qualified hardware): sensor Mac, locked ×
   unlocked, clamshell × not, external display present × absent. A sensor-less physical
   qualification is post-v1; until it is run, that mode is experimental and its close
   animation is not a release claim. Simulated no-HID tests cannot replace that run.

---

## 13. Success criteria

| # | Criterion | Measurement |
|---|---|---|
| S1 | Holds display refresh at native resolution | Frame time < 4 ms at 3456×2234 on M1 Pro baseline |
| S2 | Feels physically coupled | Angle sample to presented frame < 20 ms end to end |
| S3 | No hitch at fold start | Frame times across the first 10 frames within one refresh interval |
| S4 | Free when idle | Idle CPU < 0.2%, zero GPU work, no capture stream with lid open and static |
| S5 | Clean reversal | Reversal from any progress returns to `idle` with no visual pop; verified across replay traces |
| S6 | Fidelity to the original | Frame-matched side-by-side against real iPhone Duo footage — blur onset, void climb rate, total duration at subjective parity — committed to the repo as a GIF |
| S7 (v1) | Sensor-less mode degrades safely | Automated no-HID selection/recovery, idle ownership, immediate sleep seal, fresh post-unlock capture/unfold, permission handling, and accurate limited-mode copy. Physical sensor-less behavior and a visible close are unverified post-v1 qualifications, not v1 pass criteria. |

S6 is the one that decides whether the project met its goal. It is subjective by nature,
so it is made concrete by committing the comparison artifact to the repository where
anyone can judge it.

---

## 14. Distribution

- **Cost:** the Apple Developer Program ($99/year) is the project's *only* expense, and
  exists solely to obtain a Developer ID certificate and notary access. Everything else
  is $0: all frameworks are first-party SDK, there are no paid dependencies, and because
  §11 forbids network access there is no infrastructure to host or meter. Development and
  local testing need only a free Apple ID or ad-hoc signing.
- **License:** MIT.
- **Channel:** GitHub Releases — notarized, hardened-runtime, Developer ID signed DMG.
- **Secondary:** Homebrew cask.
- **Not the Mac App Store.** Sandbox requirements make it impossible (§11).
- **README must contain:** the Duo comparison GIF above the fold, the supported-model
  table with the sensor caveat, the permission explanation and why nothing more is needed,
  and an explanation of the fold math for the developer audience.

---

## 15. Risks and open questions

| Risk | Impact | Mitigation |
|---|---|---|
| `IOHIDDeviceOpen` gated behind Input Monitoring on some macOS versions | Changes the permission story and the trust pitch | Verify in week one, before anything is built on the assumption (§11) |
| Sensor absent on more models than expected | The unqualified path may become common and may have no visible close | Label it limited/experimental, preserve safe sleep and fresh unlock behavior, and do not claim physical sensor-less support or a close animation before hardware qualification |
| Tuning the spring and shader to actually match the original takes longer than building it | Schedule risk on the only criterion that matters (S6) | Hot-reloadable `FoldTuning` plus trace replay plus scrub mode exist specifically to compress this loop |
| Fold start hitch from capture latency despite warm-up | Kills S3, and the start is the most-watched moment | Warm band is 35° wide; if still insufficient, widen it or hold a rolling one-frame buffer |
| ScreenCaptureKit privacy indicator appearing distracting during the warm band | Perceived as spyware-ish | Warm band is brief; document it explicitly; narrowing it toward 90° is the lever |

**Note the tension between the last two rows:** a hitch at fold start argues for a *wider*
warm band, a visible privacy indicator for a *narrower* one. They are resolved against each
other empirically during M4, and 110° is the starting point, not a settled value. If both
pressures bind at once, the rolling one-frame buffer is the escape hatch, since it decouples
freshness from band width.

---

## 16. Milestones

1. **M0 — De-risk.** Read the sensor; confirm no Input Monitoring requirement; log angles
   at 60 Hz. Build trace record/replay.
2. **M1 — Feel.** `FoldDriver` with spring, hysteresis, and the full phase machine, driven
   entirely by replayed traces under unit test. No rendering at all.
3. **M2 — Pixels.** Overlay window plus freeze-frame capture plus the six render stages.
   Scrub mode. Golden-image tests.
4. **M3 — Integrate.** Wire sensor to driver to renderer. Close and open paths. The full
   edge-case list from §10.
5. **M4 — Fidelity.** Tune against real Duo footage until S6 holds. Produce the comparison
   GIF.
6. **M5 — Ship.** Safe experimental sensor-less mode (visible close best-effort, not a
   v1 guarantee), menu bar, onboarding, notarization, README, cask, `LICENSE` file
   (MIT, §14), and the GitHub Sponsors link. Physical sensor-less qualification is
   tracked after v1; all other release gates remain in force.

---

## Appendix A — Decision log

| Decision | Choice | Rationale |
|---|---|---|
| Project identity | From-scratch Swift + Metal, open source, free | Fidelity over macTilt is the goal; distribution constraints rule out the App Store anyway |
| Motion model | Angle-locked with spring momentum | Viscous slow closes, continuous reversal, jitter immunity — all three from one mechanism |
| Fold axis | Non-rigid squash into the bottom hinge | Honors real lid physics while keeping Duo's signature of pixels being consumed, not rotated |
| Opening half | Angle-tracked when unlocked, scripted unfold on unlock | The only approach that always produces an animation without touching SIP |
| Sensor-less Macs | Limited/experimental mode, identical renderer when a close is actually triggered | Safe sleep and conditional fresh post-unlock unfold in v1; visible close and physical support claims wait for a qualified public trigger and sensor-less hardware test |
| Displays | Built-in only | The effect represents a specific physical panel closing |
| Capture | Freeze-frame with speculative warm-up | Faithful to Duo's frozen UI, cheapest, and removes the first-frame hitch |

## Appendix B — References

- macTilt: https://github.com/lqSky7/iphone-duo-macos-animation
- LidAngleSensor: https://github.com/samhenrigold/LidAngleSensor
- PyBookLid: https://github.com/tcsenpai/pybooklid
- Macworld, "That amazing iPhone Duo open animation has already come to the MacBook":
  https://www.macworld.com/article/3233434/that-amazing-iphone-duo-open-animation-has-already-come-to-the-macbook.html
