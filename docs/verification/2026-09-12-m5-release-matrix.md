# M5 release verification matrix

Date started: 2026-09-12

Version candidate: 1.0.0

Status: **not shipped**

This matrix separates automated evidence from physical, credentialed, and subjective
acceptance. Unchecked rows are release blockers when they map to the M5 definition of
done. Do not infer a pass from implementation or simulation alone. Never paste captured
pixels, Apple credentials, certificate identifiers, notarization submission IDs, or
unredacted personal identifiers into this file.

## Automated regression and static gates

- [ ] Clean-checkout `swift test -Xswiftc -warnings-as-errors`
- [ ] Clean-checkout `swift build -c release -Xswiftc -warnings-as-errors`
- [ ] M3 canonical traces and resource-lifecycle suite passes
- [ ] M4 fidelity, golden-image, and performance gates pass
- [ ] CI passes on the reviewed release commit
- [ ] `Packaging/Info.plist` lint and required-key checks pass
- [ ] Minimal entitlements parse as an empty dictionary
- [ ] Universal app contains both arm64 and x86_64 slices
- [ ] Ad-hoc bundle assembly/signature verification passes

Development-only smoke, 2026-09-12: shell syntax and both plists validated; an
uncommitted working tree produced `x86_64 arm64` slices, passed ad-hoc strict signature
verification, created an unsigned local DMG, matched its generated SHA-256, and passed
`hdiutil verify`. These checks validate the tooling but do **not** satisfy the clean-
checkout, Developer ID, notarization, Gatekeeper, cask, or final-release rows above.

Development-only regression, 2026-09-13: 269/269 Swift tests and the release build
passed with warnings as errors after the lock/sleep, wake/unlock, source-handoff,
debug-overlay, and missing-lock-key recovery fixes. The latest tests also cover a
session change immediately before input starts, a late restriction during animation,
wake arriving during an in-flight unlock, and invalidation of queued menu/unlock
proof by a new lock. Metal tests required a test process
outside the restricted development sandbox; this did not grant the app new runtime
permissions. These are not clean-checkout or physical S7 evidence.

Session probe, 2026-09-13: this development Mac is a `Mac16,12` M4 MacBook Air on
macOS 26.6.2. While its desktop was visibly unlocked, `CGSessionCopyCurrentDictionary`
reported `kCGSSessionOnConsoleKey=true` but omitted `CGSSessionScreenIsLocked`.
The app therefore fails closed at startup and accepts a direct status-menu opening
as explicit user-presence evidence. Automatic startup and lock-screen behavior on
this OS still require physical observation; the menu interaction is not an S7 pass.

Cask-generator smoke, 2026-09-13: `scripts/write-cask.sh` produced a Ruby-syntax-valid
temporary cask from an ad-hoc test DMG and its matching SHA-256 sidecar, then refused
to overwrite that cask. The fixture is not Developer ID signed or notarized.
`brew style --cask` refused the `/private/tmp` file because Homebrew requires casks
to reside in a tap; style/audit/install remain unchecked release gates.

Clean candidate checkout, 2026-09-13, detached commit `0876664` on an Apple M4 Mac:
`swift test -Xswiftc -warnings-as-errors` passed 269/269; `swift build -c release
-Xswiftc -warnings-as-errors` passed. `scripts/build-app.sh --adhoc-sign --output
dist` produced a universal `x86_64 arm64` app and passed strict ad-hoc signature
verification. `scripts/make-dmg.sh` produced a **test-only**, ad-hoc DMG and checksum;
`hdiutil verify` and `shasum -a 256 -c` passed. The detached checkout was clean
before these commands. This does not prove a clean, synchronized `main` release build,
Developer ID signing, notarization, Gatekeeper, or cask installation.

Opt-in candidate performance probes at `0876664` on Apple M4: with
`LIDRIPPLE_FIDELITY_BENCHMARK=1`, the first ten native-resolution GPU frames had
2.727 ms maximum GPU time and 5.445 ms maximum submit-to-complete time against
16.667 ms; the coordinator-only S2 proxy had 0.015 ms p95 over 30 samples, and
the first ten lifecycle ticks had 0.001 ms maximum. With
`LIDRIPPLE_RENDER_BENCHMARK=1`, steady-state native-resolution render time had
0.529 ms median and 0.737 ms p95. These are this M4's development measurements,
not an M1 Pro baseline or physical end-to-end S2/S3 proof.

Cask uninstall audit, 2026-09-13: the locally installed Homebrew 6.0.9 handles
`uninstall login_item:` by asking System Events to remove a legacy login item
by name. lidripple uses `SMAppService.mainApp`, so that stanza alone does not
establish that a modern registration is removed. An installed, signed-app test
must check actual Service Management status after uninstall; any app-specific
unregistration fix must also preserve Launch at Login across cask upgrade and
reinstall. Homebrew's built-in `login_item` directive skips removal when an
upgrade successor exists, but its custom `uninstall script:` directive receives
and ignores that successor; a naive app-specific unregister script would also
run on upgrade/reinstall and could erase the user's enabled state. The uninstall
and zap rows remain unchecked.

Release-verifier smoke, 2026-09-13: shell syntax passed for all packaging scripts.
A fresh ad-hoc universal app and DMG built without replacing existing output;
the mounted DMG had an `/Applications` symlink and a byte-for-byte identical app.
The verifier rejected sidecars with a wrong filename or extra line, accepted the
correctly named sidecar, then stopped at the expected unsigned-DMG gate. A
temporary exact-checksum cask was generated. These checks do not substitute for
Developer ID, notarization, Gatekeeper, or final-cask verification.
CI now repeats per-script syntax, ad-hoc DMG mount/content checks, cask generation,
and a mislabeled-sidecar rejection. The CI row stays unchecked until that workflow
actually passes on the reviewed commit.

Latest local candidate regression, 2026-09-13, commit `4a0e3dc` on Apple M4:
`swift test -Xswiftc -warnings-as-errors` passed 269/269 and
`swift build -c release -Xswiftc -warnings-as-errors` passed. The test process
ran outside the restricted development shell sandbox because Metal tests hung
inside it; this did not change the app's runtime permissions. With the two
opt-in benchmark flags enabled, all six selected tests passed: first-ten-frame
GPU maximum 3.674 ms and submit-to-complete maximum 14.200 ms against a
16.667 ms refresh interval; steady-state median 0.529 ms and p95 0.747 ms.
These are local candidate measurements, not physical end-to-end S2/S3 proof or
CI on the reviewed release commit.

## M4 / S6 fidelity prerequisite

- [ ] `docs/fidelity/duo-comparison.gif` exists above the README fold
- [ ] Reference source, license/provenance, alignment method, and frame timing recorded
- [ ] Blur onset, void climb rate, and total duration reviewed at frame-matched parity
- [ ] Human reviewer acceptance recorded with reviewer/date

M4 status at matrix creation: pending; no GIF or subjective approval was available to
record here.

## Screen Recording and privacy (fresh macOS profile)

- [ ] Plain-language explanation appears before any TCC request
- [ ] Not Now causes no system permission prompt and does not repeat on next launch
- [ ] Continue produces only the Screen Recording request
- [ ] Denial is visible in the menu and the Settings action opens the correct pane
- [ ] Granting in Settings activates capture after app activation/relaunch
- [ ] Accessibility and Input Monitoring are never requested
- [ ] Disable and Quit tear down capture, overlay, input source, and timers
- [ ] Captured pixels do not appear on disk, in preferences, diagnostics, or logs
- [ ] App-owned network inspection shows no outbound connection
- [ ] DRM/protected content remains black and no bypass is attempted

Test machine / OS / fresh-profile identifier: pending

Evidence and redacted notes: pending

## Sensor Mac physical behavior

- [ ] Live close follows physical angle and seals cleanly
- [ ] Reversal from early/mid/late fold returns without a visual pop
- [ ] Runtime HID loss selects timed fallback after bounded recovery
- [ ] Wake promotes fallback back to HID when the sensor becomes available
- [ ] Enable, intensity endpoints, login, input, permission, and debug menu states pass
- [ ] Debug scrubber requests no TCC and leaves no timer/window/capture after close
- [ ] Fullscreen, Spaces, external display, lock/unlock, and display reconfiguration pass
- [ ] Missing lock-state-key startup activates safely without requiring an undocumented heuristic or unexpected manual action
- [ ] One-degree/raw-scale sensor caveat checked against a recorded physical sweep

Model / chip / OS: pending

Evidence and redacted notes: pending

## S7 sensor-less M2 MacBook Air

- [ ] Timed fallback is selected at launch
- [ ] Close program is approximately 550 ms and visibly begins before suspension
- [ ] Post-unlock reveal uses a fresh frame
- [ ] UI and documentation make no angle tracking or reversal claim
- [ ] Open/static state is below 0.2% CPU with zero GPU/capture/fallback timer activity
- [ ] Repeated sleep/wake remains stable
- [ ] Undetectable no-sleep clamshell behavior, if observed, is recorded

Current design blocker: `willSleep` synchronously hard-seals and tears down
ScreenCaptureKit as required by the sleep-safety contract. Its public notification
may arrive too late to display the 550 ms fallback program; the program is
implemented and unit-tested but has no production `beginFallbackClose()` caller.
Apple documents that a `willSleep` observer can delay sleep, and its power-management
QA says forced lid-close sleep can be delayed but not cancelled. Neither source
guarantees that the built-in panel remains visible after the lid switch fires
([AppKit](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification),
[IOKit QA1340](https://developer.apple.com/library/archive/qa/qa1340/_index.html)).
S7 must measure the actual M2 Air's event-to-blank interval and demonstrate a safe,
public trigger or a documented delay that keeps pixels visible. Do not ship this as
accepted S7 based on the source unit tests or a sleep-delay assumption.

For the physical timing run, execute `swift scripts/power-event-probe.swift` in a
Terminal on the M2 Air, then close/reopen the lid and stop the probe with Ctrl-C.
Record the model/OS, `registry.lidClosed`, `workspace.willSleep`, and
`screens.didSleep` uptimes, plus a human observation of the last visible frame.
The probe reads an undocumented registry property only for diagnosis; it does not
capture pixels, request sleep, delay sleep, or enable that property in production.

Model / chip: M2 MacBook Air (physical unit pending)

OS / timestamps / frame evidence: pending

S7 result: **unchecked — synthetic timing is not acceptable evidence**

## Installed app and login item

- [ ] Installed at `/Applications/lidripple.app`
- [ ] No Dock icon or normal app window (`LSUIElement` behavior)
- [ ] Launch at Login survives logout/reboot
- [ ] Approval-required state links to Login Items settings
- [ ] Unregister removes only lidripple's login item
- [ ] DMG mounts, copies, launches, quits, and ejects cleanly
- [ ] Clean account/machine Gatekeeper launch succeeds

Machine / OS / observations: pending

## Developer ID, notarization, DMG, and cask

- [ ] Inner executable and app are signed with Developer ID Application + hardened runtime
- [ ] Entitlement inspection shows no sandbox, Accessibility, Input Monitoring, network,
      or file-access entitlement
- [ ] `notarytool` reports Accepted (submission details retained privately)
- [ ] App and DMG staple validation pass
- [ ] Strict `codesign`, `spctl --type execute`, and `hdiutil verify` pass
- [ ] Final DMG SHA-256 recorded below after stapling
- [ ] Cask version, URL, and SHA-256 match the exact immutable GitHub Release artifact
- [ ] `brew style` and `brew audit --cask --strict` pass
- [ ] Cask install, launch, reinstall/upgrade, uninstall, and zap pass
- [ ] Zap inspection confirms no unrelated preferences or files are removed

Final artifact: pending

Final SHA-256: pending (must be exactly 64 lowercase hexadecimal characters)

Redacted command/result record: pending

## Public trust and authorization gates

- [ ] Copyright holder confirms the public name `Jim`
- [ ] `https://github.com/sponsors/zjimmm` is active
- [ ] README links the accepted M4 evidence and accurately describes current behavior
- [ ] Whole-milestone security/privacy/code review has no unresolved Critical/Important findings
- [ ] Owner separately authorizes commit push/tag creation
- [ ] Owner separately authorizes GitHub Release upload

Final reviewer / date / ruling: pending
