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

Development-only regression, 2026-09-13: 258/258 Swift tests and the release build
passed with warnings as errors after the lock/sleep, wake/unlock, source-handoff,
and debug-overlay race fixes. These are not clean-checkout or physical S7 evidence.

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
implemented and unit-tested but is not triggered early enough to claim this
physical acceptance row. S7 must measure an earlier public trigger on the actual
M2 Air or revise the behavior with evidence. Do not ship this as accepted S7.

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
