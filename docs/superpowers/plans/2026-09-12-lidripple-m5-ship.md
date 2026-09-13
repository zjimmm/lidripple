# lidripple Plan M5: Ship

**Goal:** Turn the completed M0-M4 implementation into a trustworthy macOS menu-bar
agent: add safe experimental sensor-less mode, persisted product controls, first-run Screen
Recording onboarding, launch-at-login, a real `LSUIElement` application bundle, and a
verified Developer ID/notarized release path with the public documentation and project
metadata required by the PRD.

**Prerequisite:** Execute this plan only after M4 is merged and its S6 comparison GIF,
report, tuning, provenance, and human approval are committed. The GIF is an input to the
README, not an M5 substitute for incomplete fidelity work. Rebase this plan's file list
against the final M4 target names before editing `Package.swift`; M4 currently has active
changes there.

**Current baseline:** M3 exposes a generation-gated HID input path, bounded sensor
recovery, `sensorUnavailable()` / `sensorRecovered()`, pixel-free diagnostics, one
capture/overlay lifecycle, and enable/disable. The app is still an unbundled SwiftPM
executable whose status menu contains only Quit. `FoldTuning.withIntensity(_:)` already
enforces FR-17, and the renderer already accepts live tuning updates. There is no
`EventAngleSource`, preferences controller, permission onboarding, login-item binding,
Info.plist, signed artifact pipeline, top-level README, cask, license, or Sponsors
metadata.

**Architecture:** Add a deterministic `EventAngleSource` beside the HID adapter, and
move source selection/replacement plus application policy out of `AppDelegate` into a
testable `LidRippleAppSupport` target. `InputSourceController` owns exactly one
`any LidAngleSource`, keeps the existing generation gate, prefers HID, and falls back
after the existing bounded recovery policy. `AppCoordinator` composes that controller,
the M3 lifecycle, permission policy, preferences, and menu/debug UI. Platform services
(TCC, `SMAppService`, settings/browser opening, defaults, and alerts) sit behind narrow
protocols so ordinary tests cannot trigger permission prompts, login-item changes, or
network/browser activity.

**Constraints:** Swift 6, macOS 14+, no third-party runtime dependency, App Sandbox off,
hardened runtime on for distribution, and no captured pixels on disk, in defaults, in
logs, or in diagnostics. The installed app itself makes no outbound network connection;
"Check for Updates" may only hand the GitHub Releases URL to the user's default browser.
No Accessibility or Input Monitoring request may be added. The app must remain inert
when disabled or idle, and fallback mode must use the exact same driver, capture,
overlay, renderer, and M4 tuning as sensor mode.

## Requirement traceability

| Requirement | M5 implementation | Evidence |
|---|---|---|
| G4, FR-11 | No-HID selection and safe sleep seal; `EventAngleSource` stays idle until a future qualified early visible-close trigger | deterministic source/recovery/sleep tests; real no-HID hardware remains unverified post-v1 |
| FR-12 | Read-only menu row reports sensor, experimental sensor-less, or unavailable mode with explicit close limitations | menu-model and source-transition tests plus copy review |
| FR-15 | Bundled app has `LSUIElement=true`; no Dock icon or normal app window | plist assertion plus installed-app smoke |
| FR-16 | Enable, intensity, login item, input mode, permission, and debug scrubber are all present | menu action tests and manual UI pass |
| FR-17 | Persisted 0.5-1.0 intensity updates only blur radius, rotation, and squash gain | existing core contract plus live-output tests |
| PRD §11 | Plain-language pre-prompt; denial state and Settings link; no extra permissions; GPU-only ephemeral capture | permission state-machine tests, fresh-profile manual run, README |
| S4 | Disabled/idle/fallback-waiting owns no capture, drawable clock, or active fallback timer | lifecycle and timer-idleness assertions plus Activity Monitor/GPU check |
| S7 (v1) | Safe experimental sensor-less degradation, not a guaranteed visible close | automated no-HID selection/recovery, idle/teardown, fresh-unlock, permission, and copy tests; physical no-HID qualification remains post-v1 and unclaimed |
| PRD §14 | Universal notarized Developer ID DMG on GitHub Releases; Homebrew cask; MIT | artifact verification log, cask audit/install, LICENSE |

## Input and fallback contract

`EventAngleSource` conforms to the existing `LidAngleSource`; it does not add a second
driver or a progress-only bypass. Its injected clock/scheduler makes output fully
deterministic in tests. It emits samples only during a requested transition and owns no
timer while stopped or waiting for an event.

- Only a demonstrated early public trigger may start a visible close. If one is
  qualified, `EventAngleSource` emits a monotonic decreasing angle program at 60 Hz.
  Its phase landmarks cross the driver's arm, fold-start, fold-end, and seal thresholds
  in order, with enough warm-band time for the normal speculative capture path. The
  final sample is below `sealAngle`; the source does not call private lifecycle methods.
  No such production trigger is established for v1; `willSleep` must not start the ramp.
- The source's nominal close program is approximately 550 ms. Keep its duration and
  landmark fractions in one Codable `EventAngleTuning` value, not scattered timer
  literals, and test the resulting coordinator phase history. A passing synthetic
  timeline does not establish that real hardware displays those frames.
- Locked physical opening never attempts to draw above `loginwindow`. Wake/unlock uses
  M3's fresh-frame scripted unfold. The input controller suppresses fallback samples
  while the session is restricted, so it cannot race that path.
- Duplicate sleep/wake notifications are idempotent. A reverse event cancels the prior
  program before a new one begins; stopping/replacing a source invalidates all queued
  samples with the same generation rule as HID.
- `willSleep` immediately hard-seals and tears down capture. It is not an early-close
  trigger: an owner-run probe on a sensor-equipped M2 Air observed the built-in panel
  black immediately and `willSleep` within the lid-closed polling interval. This does
  not prove every Mac's timing, but it cannot substantiate a 550 ms visible fallback.
  Do not delay forced sleep or add undocumented/private production hooks.
- Physical no-HID qualification is post-v1. Until an actual sensor-less Mac shows a
  supported early trigger and visible time, product copy must say a close animation
  may be absent; no simulated result or sensor-equipped test counts as hardware proof.
- In fallback mode, clamshell closure without sleep may be undetectable and physical
  reversal is unavailable. State both limitations in the mode help text and README as
  FR-12 requires.

## Planned files

| Path | Responsibility |
|---|---|
| `Sources/LidRippleSensor/EventAngleSource.swift` | Idle-free scheduled fallback implementing `LidAngleSource` |
| `Sources/LidRippleSensor/EventAngleTuning.swift` | Codable nominal 550 ms ramp duration and threshold-relative landmarks; not a visibility claim |
| `Tests/LidRippleSensorTests/EventAngleSourceTests.swift` | Fake-clock timing, ordering, cancellation, and idleness |
| `Sources/LidRippleAppSupport/InputSourceController.swift` | HID-first selection, recovery, fallback, generations, event routing |
| `Sources/LidRippleAppSupport/AppCoordinator.swift` | Product composition and app lifecycle policy |
| `Sources/LidRippleAppSupport/AppPreferences.swift` | Typed defaults for enable, intensity, launch-at-login, onboarding |
| `Sources/LidRippleAppSupport/MenuBarController.swift` | Complete FR-16 menu and status refresh |
| `Sources/LidRippleAppSupport/DebugScrubberController.swift` | Permission-free in-app slider/ramp using the sole overlay |
| `Sources/LidRippleAppSupport/ScreenRecordingPermission.swift` | TCC preflight/request state and Settings routing |
| `Sources/LidRippleAppSupport/OnboardingController.swift` | Explain-before-request first-run flow |
| `Sources/LidRippleAppSupport/LaunchAtLoginController.swift` | `SMAppService.mainApp` adapter and error/status mapping |
| `Sources/LidRippleApp/AppDelegate.swift` | Thin NSApplication bridge into `AppCoordinator` |
| `Tests/LidRippleAppSupportTests/*` | Policy, menu, preference, permission, login, and debug tests |
| `Packaging/Info.plist` | Agent bundle metadata and minimum OS/version substitutions |
| `Packaging/lidripple.entitlements` | Auditable empty/non-sandbox entitlement set |
| `Packaging/AppIcon.icns` | Original app/release artifact icon |
| `VERSION` | Single release version source; initial v1 value `1.0.0` |
| `scripts/build-app.sh` | Release/universal bundle assembly and optional ad-hoc signing |
| `scripts/make-dmg.sh` | Deterministic staging and DMG creation |
| `scripts/sign-and-notarize.sh` | Developer ID signing, notary submission, stapling |
| `scripts/verify-release.sh` | Architecture, plist, signature, Gatekeeper, staple, and DMG checks |
| `.github/workflows/ci.yml` | Permission-free tests, release build, and unsigned bundle validation |
| `docs/releasing.md` | Credential setup and exact tag/artifact/cask release sequence |
| `docs/verification/2026-09-12-m5-release-matrix.md` | Physical, TCC, login, fallback, and installed-artifact evidence |
| `README.md` | Product, GIF, compatibility, permissions/privacy, install, math, development |
| `Casks/lidripple.rb` | Versioned GitHub Release cask with exact SHA-256 |
| `LICENSE` | MIT license, copyright 2026 Jim |
| `.github/FUNDING.yml` | GitHub Sponsors metadata for `zjimmm` |

## Task 1: Timed fallback source

- [ ] Add `EventAngleTuning` and `EventAngleSource` to `LidRippleSensor`. Inject a
      monotonic clock and repeating scheduler; production uses a serial 60 Hz timer,
      while tests advance virtual time without sleeping.
- [ ] Define explicit source events for close/sleep, wake/unlock, session restriction,
      and cancellation. Keep NSWorkspace observation in the app layer; the source is a
      small state machine, not a global notification observer.
- [ ] Generate threshold-relative angles from the active `FoldTuning`, including a real
      armed warm interval, fold interval, and terminal angle below the seal threshold.
      Do not duplicate hard-coded 110/75/25/12 values.
- [ ] Ensure every emitted timestamp is strictly increasing, output is exactly 60 Hz
      within floating-point tolerance, start/stop are idempotent, and no handler is
      retained after stop.
- [ ] Replay the source through a real `FoldDriver` and fake M3 lifecycle. Assert ordered
      `idle -> armed -> folding -> sealed`, approximately 550 ms nominal program timing,
      one warm/freeze cycle, and no distinct renderer path. Do not infer visibility on
      physical hardware from this test.
- [ ] Cover duplicate notifications, cancellation on every landmark, stop-from-handler,
      clock jumps, delayed ticks, wake while restricted, and source deallocation. Assert
      zero scheduled work before an event and after terminal delivery (S4).

## Task 2: Atomic HID/fallback ownership

- [ ] Add `LidRippleAppSupport` and its test target. Move the existing app-policy code
      out of the executable target; leave `main.swift` and `AppDelegate` as thin bridges.
- [ ] Implement `InputSourceController` with injected HID/fallback factories and the
      existing `SensorRecovery`. Probe HID first without prompting. Select fallback at
      launch if absent, or after bounded runtime recovery fails; retry HID on wake and
      atomically promote back when it succeeds.
- [ ] Preserve and centralize the source-generation token. A stopped HID callback or
      cancelled fallback tick must never reach `FoldLifecycleCoordinator` after a newer
      source is installed.
- [ ] Generalize M3 diagnostics from `sensor` / `fallbackRequired` to
      `sensor` / `timedFallback` / `unavailable`. Input availability must remain
      orthogonal to enabled, session, display, permission, and capture state.
- [ ] Route workspace sleep/wake and lock/session notifications through the controller.
      The selected source gets relevant events; M3 still owns hard seal, locked drawing
      suppression, fresh unlock capture, and teardown. `systemWillSleep()` must seal
      synchronously without starting a fallback close. A future qualified early trigger
      needs its own ordering test before it can be connected.
- [ ] Test launch selection, HID-start failure, recovery on every retry, exhaustion,
      fallback-to-HID promotion, repeated wake, disable/enable, termination, and stale
      callbacks from both source types. Assert one source, one timer, one lifecycle, one
      capture, and one overlay at all times.

## Task 3: Persisted controls, live intensity, and complete menu

- [ ] Add typed `AppPreferences` over injected storage. Defaults are enabled `true`,
      intensity `1.0`, launch-at-login `false`; clamp/migrate intensity to `0.5...1.0`.
      Do not persist phase, angles, capture state, pixel data, or diagnostic errors.
- [ ] Add a live renderer-tuning method through `FoldLifecycleOutput` /
      `OverlayLifecycleOutput` / `OverlayPresenter`. Always start from the final M4
      tuning and call `withIntensity`; changing intensity must not reconstruct the
      driver, alter thresholds/spring/timing, start capture, or show the overlay.
- [ ] Make Disable stop input/recovery/fallback timers and call M3 `setEnabled(false)` so
      capture and presentation are torn down. Re-enable re-evaluates permission/display,
      selects a source cleanly, and cannot revive stale work.
- [ ] Build the menu in this order: Enable checkbox; intensity slider with 50%-100% and
      numeric value; Launch at Login checkbox; read-only Input Mode row; read-only or
      actionable Screen Recording row; Open Debug Scrubber; Check for Updates; Quit.
      Refresh states whenever preferences, permission, source, or login status changes.
- [ ] `Check for Updates` opens `https://github.com/zjimmm/lidripple/releases` in the
      default browser and performs no in-process request. Failures are shown, not logged
      as success.
- [ ] Add menu-model/action tests for every state and transition, including disabled,
      sensor, fallback, unavailable, permission-needed, login approval-needed, and
      reduced intensity. Add one main-actor AppKit smoke test without opening TCC.

## Task 4: Permission-free debug scrubber

- [ ] Reuse the existing preview concepts in an in-app `DebugScrubberController`: a
      utility panel with continuous progress slider, fold/reverse playback, current
      progress, and reset/close controls. Give the menu command a discoverable shortcut.
- [ ] Entering debug mode first disables live input and waits for lifecycle capture
      teardown, then installs a generated checkerboard/gradient source into the sole
      `OverlayPresenter`. It must not request Screen Recording or expose a desktop frame.
- [ ] Keep MTKView's internal clock paused; the scrubber owns at most one 60 Hz playback
      timer and advances the same renderer/state types. Closing it clears the synthetic
      texture, hides the overlay, stops the timer, and restores the user's enabled state
      and preferred input source.
- [ ] Apply current intensity and final M4 tuning in scrub mode. Changes made while the
      panel is open update immediately and remain subject to FR-17.
- [ ] Test slider endpoints, forward/reverse, repeated open/close, close while playing,
      enable restoration, source restoration, no capture calls, no TCC calls, and no
      orphaned timer/window. Keep the standalone `lidripple-preview` development tool.

## Task 5: Screen Recording onboarding and permission state

- [ ] Define `ScreenRecordingPermissionState` as `notDetermined`, `granted`, or `denied`.
      Resolve it from injected `CGPreflightScreenCaptureAccess` plus the persisted fact
      that a request was made; refresh on app activation so Settings changes appear
      without relaunch.
- [ ] On first enabled launch, present a native explanation before any call capable of
      prompting. State plainly: lidripple briefly captures only the built-in display,
      excludes its overlay, keeps one frame in GPU memory, writes nothing, sends nothing,
      and needs no Accessibility or Input Monitoring access. Offer Continue and Not Now.
- [ ] Call `CGRequestScreenCaptureAccess` only after Continue. Not Now leaves the app
      installed and the menu useful without repeatedly prompting. A false result becomes
      a visible `Screen Recording: Needs Permission` menu action.
- [ ] Deep-link the action to the Screen Recording pane. Centralize the URL and provide a
      Privacy & Security root fallback; manually verify routing on every supported major
      macOS version rather than assuming one private URL shape remains stable.
- [ ] Gate runtime capture when permission is known absent. The app may remain enabled,
      but must not churn warm/freeze attempts or fail silently; diagnostics/menu explain
      the blocked state. Granting permission reactivates the pipeline cleanly.
- [ ] Test request ordering, Continue, Not Now, deny, grant-before-launch, grant-after-
      Settings, repeated launch, disabled first launch, settings-open failure, and the
      guarantee that ordinary `swift test` never invokes real TCC APIs.

## Task 6: Launch at login and real application bundle

- [ ] Implement `LaunchAtLoginController` over `SMAppService.mainApp`, exposing enabled,
      disabled, requires-user-approval, and unavailable/error states. Register/unregister
      only after a user menu action; reconcile the persisted preference with service
      truth at launch instead of blindly toggling it.
- [ ] If ServiceManagement requires approval, surface that state and offer the public
      Login Items settings route. On failure, restore the checkbox to actual service
      state and show an actionable error.
- [ ] Add `VERSION` with `1.0.0` and a tokenized `Packaging/Info.plist` containing
      `CFBundleIdentifier=com.lidripple.app`, display/name `lidripple`, executable
      `lidripple`, `APPL`, semantic/build versions, `LSMinimumSystemVersion=14.0`, high-
      resolution support, and `LSUIElement=true`. Keep the runtime accessory policy as a
      defense in depth, not as the bundle's primary agent declaration.
- [ ] Add an original `.icns` with all required representations. Do not reuse Apple/Duo
      marks or reference-footage frames in the icon.
- [ ] Build release executables separately for `arm64` and `x86_64`, combine them with
      `lipo`, assemble `lidripple.app`, validate the plist, and support ad-hoc signing for
      local testing. Verify both slices before claiming Apple Silicon and Intel support.
- [ ] Add bundle tests/scripts that fail on missing keys, mismatched version/executable,
      wrong minimum OS, Sandbox entitlement, unexpected permission entitlement, missing
      architecture, non-agent activation, or files outside the documented bundle set.
- [ ] Install the ad-hoc app into a temporary Applications-equivalent path and test
      launch/quit plus `SMAppService` status without registering a real login item in
      automated tests. Perform actual register/reboot/login/unregister manually from
      `/Applications/lidripple.app`.

## Task 7: Developer ID, hardened runtime, notarized DMG, and release verification

- [ ] Keep `lidripple.entitlements` intentionally minimal: App Sandbox is absent and no
      Accessibility, Input Monitoring, network client/server, or file-access entitlement
      is present. Document why ScreenCaptureKit and this HID path need no added
      entitlement. Treat any entitlement addition as a security review change.
- [ ] Make `build-app.sh` deterministic about inputs and fail on dirty/mismatched version
      state for a release build. Make `make-dmg.sh` stage only the app plus an Applications
      symlink, use a stable volume name, and emit SHA-256 beside the artifact.
- [ ] Make `sign-and-notarize.sh` require an explicit Developer ID Application identity
      and either a named `notarytool` keychain profile or App Store Connect API-key
      arguments. Sign the inner universal executable and bundle with hardened runtime and
      timestamp, create/sign the DMG, submit with `xcrun notarytool --wait`, then staple.
      Never print credentials or store them in the repo.
- [ ] Make `verify-release.sh` run `plutil`, `lipo`, strict `codesign` validation,
      entitlement inspection, `spctl --type execute`, `hdiutil verify`, `stapler validate`,
      mount/copy/launch smoke, and an assertion that the installed binary matches the
      cask checksum. Save a redacted command/result record in the M5 release matrix.
- [ ] Add CI on supported macOS runners for warnings-as-errors tests/release build,
      universal assembly where both SDK slices are available, plist inspection, ad-hoc
      signing, and static package checks. Real Developer ID/notary credentials remain an
      explicit maintainer release gate, not a fake CI pass.
- [ ] Document the release sequence: verify clean `main`; build/sign/notarize; run all
      checks; write the exact DMG SHA into the cask; audit/install the cask against the
      local artifact; commit; tag `v1.0.0`; push; then, only with owner authorization,
      upload that exact immutable DMG and checksum to GitHub Releases. Never rebuild
      between checksum, tag, and upload.

## Task 8: Public trust surface and distribution metadata

- [ ] Add the standard MIT text in `LICENSE` with `Copyright (c) 2026 Jim`. Confirm the
      desired public copyright name before the release tag; changing the name does not
      change the license terms.
- [ ] Add `.github/FUNDING.yml` with `github: [zjimmm]` and a visible README Sponsors link.
      Verify the Sponsors profile is active before publishing so the link is not a dead
      trust signal.
- [ ] Put `docs/fidelity/duo-comparison.gif` above the README fold with M4 attribution.
      The README must also include: concise demo/requirements; install and uninstall;
      supported-model table with sensor/experimental sensor-less mode and the current
      1-degree/raw-scale caveat; menu controls; unavailable visible-close limitations;
      Screen Recording rationale and denial
      recovery; explicit no Accessibility/Input Monitoring/network/telemetry/disk-capture
      statements; DRM black-frame behavior; brief fold/spring/shader math; build/test;
      troubleshooting; license; Sponsors; and links to fidelity/sensor evidence.
- [ ] Add a tap-style `Casks/lidripple.rb` for the exact `v1.0.0` GitHub Release URL and
      exact DMG SHA-256. Include `depends_on macos: ">= :sonoma"`, the app artifact,
      launch-at-login cleanup, and an explicit zap stanza limited to lidripple defaults
      and service state. Do not use `sha256 :no_check`.
- [ ] Run `brew style`, `brew audit --cask --strict`, install, launch, upgrade/reinstall,
      uninstall, and zap against the notarized artifact. Verify uninstall does not remove
      unrelated preferences or user files.
- [ ] Add `docs/releasing.md` with credential prerequisites, no-secret logging rules,
      version/tag/cask invariants, notarization troubleshooting, rollback, and the owner-
      approval boundary for pushes/tags/releases.

## Task 9: v1 S7, privacy, and final release gates

- [ ] Run `swift test -Xswiftc -warnings-as-errors` and
      `swift build -c release -Xswiftc -warnings-as-errors` from a clean checkout, then
      rerun M3's canonical traces/resource tests and M4's fidelity/golden/performance
      gates. Menu/package work must not regress S1-S6.
- [ ] On a fresh macOS user profile, verify: explanation appears before TCC; Not Now does
      not prompt; denial is visible and links correctly; grant activates capture; no
      Accessibility/Input Monitoring request appears; disable tears down; quit cleans up.
- [ ] On the sensor Mac, verify live close/reversal, runtime HID loss to fallback, wake
      promotion back to HID, all menu states, each intensity endpoint, debug scrubber,
      fullscreen/Spaces, DRM black content, and no stale capture after lock/unlock.
- [ ] For v1 S7, verify no-HID selection/recovery, no scheduled idle timer/capture/drawable work,
      synchronous sleep seal and teardown, stale-callback suppression, fresh-frame
      post-unlock unfold, permission gating, and accurate experimental-mode copy with
      deterministic tests. A forced-no-HID run on a sensor-equipped Mac is simulation,
      not physical qualification. Keep the actual sensor-less hardware row explicitly
      unverified and post-v1; do not advertise its close animation as available. S4's
      measured idle CPU and zero GPU gate remains separate and must not be inferred
      from these deterministic tests.
- [ ] From `/Applications`, verify LSUIElement behavior, launch-at-login across a real
      logout/reboot, Gatekeeper on a clean machine/account, DMG mount/copy/eject, and cask
      install/uninstall. Confirm Activity Monitor/network tooling shows no app-owned
      outbound connections and captured frames never reach disk.
- [ ] Perform a whole-milestone security/privacy/code review. Resolve all Critical and
      Important findings, rerun every automated/artifact/manual gate, and record honest
      unchecked rows for hardware or credentials that were not available.
- [ ] Commit M5 as one milestone boundary after its review. Push `main` only with the
      user's explicit remote-write approval. Create/tag/publish the release only with
      separate explicit authorization, using the already verified immutable artifact.

## Definition of done

- [ ] FR-11/FR-12 and v1 S7 safe-degradation tests pass. The sensor-less mode is labeled
      experimental/unverified on real no-HID hardware, with no guaranteed visible close,
      angle tracking, or mid-close reversal. Physical no-HID qualification remains
      post-v1 and cannot be inferred from a sensor-equipped M2 Air.
- [ ] FR-15/FR-16/FR-17 hold in the installed app, preferences persist, and every disable,
      debug, source-replacement, and termination path leaves no orphaned work.
- [ ] Screen Recording is the only requested TCC permission, explanation always precedes
      the request, denial is actionable, and privacy claims match both code and observed
      behavior.
- [ ] The app is a universal `LSUIElement` bundle with minimal entitlements, hardened
      Developer ID signature, accepted/stapled notarization, clean Gatekeeper assessment,
      and verified DMG.
- [ ] README, M4 GIF, supported-model caveats, math, LICENSE, Sponsors metadata, cask, and
      release documentation are complete and internally consistent.
- [ ] The cask's version, URL, and SHA identify the exact notarized artifact attached to
      the corresponding GitHub release; no placeholder checksum or mutable rebuild exists.
- [ ] Full tests/builds, M3/M4 regressions, CI, Homebrew checks, installed-app checks,
      permission/manual matrix, security review, and release verification are green or
      explicitly recorded as not yet satisfied. Nothing is called shipped while a v1 S7,
      signing, notarization, or release-artifact gate remains unchecked. The separate
      post-v1 physical no-HID row must remain labeled unverified, not silently passed.
