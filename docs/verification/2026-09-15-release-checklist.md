# LidRipple release checklist

Created: 2026-09-15. Owner: Jim.

**Status: not ready for public release.**
**Direction:** open source under the existing MIT license. The owner reversed the
paid-app proposal on 2026-09-15; pricing, checkout, trials, and activation are no
longer launch requirements. Keep the simple, ungated experience.
Baseline: `931da8b` (PRD and branding). Final candidate commit, version, build number,
artifact checksum, and release date: not yet selected.

Purpose: ship a delightful, dependable app for casual MacBook owners. Preserve the
approved Fold/Ripple visuals and icon; do not add setup or customization friction.

## How to use this checklist

Unchecked items are pending, not assumed failures. Every required gate must have a
dated result tied to the final candidate. Record machine/model, macOS version,
effect, result, and a sanitized evidence link. Never store credentials, license
secrets, personal information, or private desktop captures here.

Jim owns product, rights, and physical acceptance. Engineering owns fixes,
automation, packaging, and evidence. A local development build or an old test pass
does not qualify the final release artifact.

## 1. Approved product baseline

- [x] Name is **LidRipple**, with stable internal bundle ID `com.lidripple.app`.
- [x] Fold and Ripple included, with curated strength defaults.
- [x] Compact illustrative preview; no Screen Recording needed for the preview.
- [x] No public intensity slider, calibration exercise, setup checklist, or timed pause.
- [x] Owner accepted the frosted wake handoff and current visuals.
- [x] Owner selected the graphite/pearl app icon; simpler template menu-bar mark retained.
- [x] Previous PRD and branding committed/pushed at `931da8b`.
- [x] Owner chose to keep the project open source on 2026-09-15.
- [x] Update the PRD's superseded paid/proprietary direction to match this decision.

Prior evidence: 310 automated tests passed before that commit. This is a baseline,
not a substitute for the final-candidate checks below.

## 2. Immediate engineering blockers

- [x] Correct the stale lowercase `CFBundleDisplayName` and `CFBundleName` expectations
  in `.github/workflows/ci.yml` and `scripts/verify-release.sh` to `LidRipple`.
  Keep `CFBundleExecutable=lidripple` and `CFBundleIdentifier=com.lidripple.app` unchanged.
  Fixed on 2026-09-15; final candidate CI remains a separate gate.
- [ ] Verify renamed `LidRipple.app` paths throughout build, DMG, install, cask, and CI.
- [ ] Provide public source and a reachable update/download destination. The last
  verified repository was private; confirm visibility before launch. Audit the source
  and history before requesting explicit owner approval to make it public. Updating
  this checklist does not change repository visibility.
- [ ] Resolve all blocking findings from the release matrices linked below, or record
  explicit owner-approved scope changes. Do not silently treat pending work as passed.

## 3. First launch: install, grant permission, enjoy

Run on a fresh macOS user/profile with the final downloaded artifact.

- [ ] DMG opens normally; drag-to-Applications instruction and app identity are clear.
- [ ] App opens from Applications without bypass commands or developer tools.
- [ ] One short permission explanation; no calibration or angle-setting task.
- [ ] Grant Screen Recording: the app recovers reliably, including any required restart.
- [ ] Deny/Not Now: clear permission recovery remains available; no repeated nagging.
- [ ] Revoke permission while running: overlay clears safely; regrant/restart recovers.
- [ ] Preview works before permission and never covers or captures the whole desktop.
- [ ] Enable, effect choice, and Launch at Login persist through quit/relaunch.
- [ ] Launch at Login works after a real login; turning it off removes registration.
- [ ] Replacing an older installation leaves one intended app, no duplicate process,
  and no stale login item. Check lowercase-to-capitalized bundle replacement too.

## 4. Physical motion acceptance

Required: owner's M4 MacBook Air and M2 MacBook Air, both Fold and Ripple.
Owner confirmation, 2026-09-15: physical lid tests are all OK; do not repeat them.
The matrix below is accepted by owner attestation, not new instrumented measurements.
The owner also explicitly waived repeating these tests on the final packaged build.
Record actual sensor detection: the M2 previously reported a sensor and is not a
valid sensor-less test merely because of its model name.

| Scenario | M4 Fold | M4 Ripple | M2 Fold | M2 Ripple |
|---|---|---|---|---|
| Slow close and reopen | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| Quick close/reversal before sleep | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| Hold partly open, then continue | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| Full sleep, then slow opening | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| Auto-unlock, if configured | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| Remain locked, then manually unlock | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| Close again immediately after reopening | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| Full-screen app and Space change | Owner accepted | Owner accepted | Owner accepted | Owner accepted |
| External display connect/disconnect and clamshell | Owner accepted | Owner accepted | Owner accepted | Owner accepted |

- [ ] No one-frame snap, duplicated recognizable desktop, or persistent cover.
- [ ] Movement feels coupled to the lid; holding the lid holds the effect.
- [ ] Lock/sleep clears captured content. No pre-lock desktop shown while locked.
- [ ] Wake handoff is acceptable to Jim; document remaining system-desktop flash honestly.
- [ ] External displays remain untouched; missing built-in display fails safely.
- [ ] Repeat close/sleep/open cycles at least ten times per machine without stuck state.
- [ ] Define and disclose the tested macOS/model support range. Do not claim every
  macOS 14+ machine is physically qualified just because that is the deployment target.
- [ ] Keep no-HID fallback experimental/unverified unless a genuine no-sensor machine
  is qualified. No guaranteed visible close or angle tracking in that mode.

## 5. Final-candidate technical verification

- [ ] Record version/build and freeze the exact source commit; clean worktree.
- [ ] Run `swift test -Xswiftc -warnings-as-errors` on the clean candidate.
- [ ] Run `swift build -c release -Xswiftc -warnings-as-errors`.
- [ ] CI passes on the exact release commit, including packaging checks.
- [ ] Verify both effects' trace/reversal, render, lock, capture, and timeout coverage.
- [ ] Measure first-frame and steady-state rendering, idle CPU/GPU, and wake behavior
  on target hardware. Record metrics; do not equate GPU time with end-to-end latency.
- [ ] Check sustained operation on battery and Low Power Mode for visible regressions.
- [ ] Confirm preview/timers/capture stop when no longer needed; quit clears all overlays.
- [ ] Check Reduce Motion behavior and keyboard/VoiceOver access to product controls.
- [ ] Audit shipped assets/notices and ensure no secrets or development artifacts ship.

## 6. Signing, packaging, and delivery

- [x] Select Developer ID signing credentials; Apple Development is not release evidence.
  Developer ID Application identity verified locally on 2026-09-15. Owner configured
  and validated notarization credentials in Keychain; no secrets stored in the repository.
- [ ] Build universal `LidRipple.app` using the final version/build and approved icon.
- [ ] Verify hardened runtime, intended entitlements, signature, and both architectures.
- [ ] Notarize/staple the app and final DMG using the existing release scripts.
- [ ] Verify the final DMG SHA-256 sidecar and preserve the exact artifact.
- [ ] Run `scripts/verify-release.sh` against that app/DMG after fixing its name assertions.
- [ ] Decide whether Homebrew is included at launch. The current final verifier expects
  a cask; either provide/verify it or explicitly update that release contract first.
- [ ] Download through the public release URL on another Mac; verify Gatekeeper and
  launch with quarantine intact. No `xattr` bypass as a normal installation step.
- [ ] Test update/replacement from the previous build and retain a known-good rollback.
- [ ] Confirm app icon/name display correctly in Finder, permission settings, and installer.

## 7. Open-source readiness

- [ ] Retain the MIT license and verify copyright attribution and third-party notices.
- [ ] Review source, git history, documentation, and bundled assets for secrets,
  private data, and redistribution rights before public visibility changes.
- [ ] Document source-build prerequisites and commands; verify them from a fresh clone.
- [ ] Link each downloadable release to its source tag/commit and checksum.
- [ ] Provide concise contribution guidance, bug-report instructions, and a private
  route for security reports. Explain that reports must not include desktop captures
  containing personal information.
- [ ] Publish a privacy explanation and support/issue-reporting destination.
- [ ] Keep both effects available without purchase, activation, accounts, or trials.
- [ ] Document update networking accurately; never transmit screen content.
- [ ] Optional donations/sponsorship are not launch blockers or feature gates.

## 8. Release page and honest demonstration

- [ ] Record a short owner-created real-device demo of both closing and opening effects.
- [ ] Use only owned/licensed artwork and permission-cleared footage.
- [ ] Resolve PRD S6: provide the rights-cleared reference comparison, or explicitly
  revise/waive that criterion with Jim. Visual approval is not frame-matched proof.
- [ ] Explain sensor requirements, Screen Recording, post-unlock-only effects, and
  best-effort wake behavior before download. No promise of lock-screen animation.
- [ ] No Apple affiliation, pixel-identical, universal compatibility, or zero-flicker claims.
- [ ] Publish clear install, permission-recovery, uninstall, update, and support instructions.

## 9. Go / no-go

- [ ] All required sections above pass against the final candidate, with evidence.
- [ ] Any deferral lists its user impact and has explicit owner approval; safety,
  privacy, and distribution access are not silently waived.
- [x] Jim waived repeating physical tests on the final build (2026-09-15); prior physical acceptance stands. Final artifact signature, installation, and Gatekeeper checks are still required.
- [ ] Public source, downloads, support, and rollback are ready before announcing release.
- [ ] Publish release notes and exact artifact/checksum; verify access while signed out.
- [ ] Review early support reports for permission, compatibility, and wake issues before
  spending effort on new effects.

## Evidence and related documents

- [Current PRD](../superpowers/specs/2026-09-12-lidripple-design.md)
- [Original M5 release matrix](2026-09-12-m5-release-matrix.md)
- [M3 physical matrix](2026-09-12-m3-manual-matrix.md)
- [Owner-accepted opening handoff](2026-09-14-opening-continuity.md)
- [Icon provenance and editing prompts](../../Packaging/AppIcon-artwork.md)

This checklist organizes existing gates plus open-source publication readiness. It
does not mark historical unchecked release gates complete or authorize publication
or repository visibility changes.
