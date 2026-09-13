# Decision: sensor-less v1 acceptance

Status: **approved by the owner on 2026-09-13; reflected in the PRD and M5 plan**

This records the approved narrower v1 promise for Macs without a validated
lid-angle sensor. The PRD, M5 plan, release matrix, and app mode copy have been
revised together. This decision does **not** mark any release gate complete.

## Why a decision is needed

The prior [PRD](superpowers/specs/2026-09-12-lidripple-design.md) made a
roughly 550 ms visible close on a sensor-less M2 MacBook Air part of FR-11 and
S7. The prior [M5 plan](superpowers/plans/2026-09-12-lidripple-m5-ship.md)
required physical S7 acceptance and revision of the trigger design if the
public sleep notification arrived too late. Production currently has no caller
for `beginFallbackClose()`; `willSleep` immediately seals and releases capture.

The [physical timing record](verification/2026-09-12-m5-release-matrix.md)
from 2026-09-13 observed `workspace.willSleep` only 1.597 ms after a polled
lid-closed event on one close, and within the 60 Hz poll interval on another.
The owner saw the built-in panel go black immediately. That Mac subsequently
reported a responding lid-angle sensor, so it **does not** qualify as the
sensor-less S7 test machine. The observation still makes a 550 ms visible
program starting at `willSleep` implausible on that unit; it does not prove
timing on every Mac or rule out every future public trigger. Apple's
[power-management guidance](https://developer.apple.com/library/archive/qa/qa1340/_index.html)
distinguishes forced lid-close sleep from idle sleep and says forced sleep can
be delayed but not prevented. It does not promise that the built-in panel
continues showing frames after the lid switch.

No genuinely sensor-less Mac is available for this release candidate. Keeping
the former S7 unchanged would keep M5 unverified. Relabeling unit tests
or a forced-fallback run on a sensor-equipped Mac as a physical S7 pass would
not solve that gap.

## Approved v1 contract

These replacements are now incorporated in the PRD and M5 plan:

| PRD location | Approved contract |
|---|---|
| G4 | On a Mac without a validated lid-angle sensor, fail safely at sleep and provide a fresh scripted unfold after unlock when the session and Screen Recording permission allow it. A close animation is opportunistic, not guaranteed. |
| FR-11 | Probe the HID sensor at launch. If absent or lost after bounded recovery, select a sensor-less mode using the same `FoldDriver`, capture, overlay, renderer, and tuning. Keep its synthetic source and timer idle until a safe trigger exists. A roughly 550 ms close may run only when a public trigger is measured to arrive while the built-in panel can still display it; otherwise `willSleep` immediately seals and tears down capture without a visible close. Never delay forced sleep, use an undocumented production hook, or draw over `loginwindow`. |
| FR-12 | The menu and README identify sensor-less mode as limited or experimental. They must say plainly that close animation may be absent, physical angle tracking and mid-close reversal are unavailable, and a no-sleep clamshell close may be undetectable. They must not imply that a 550 ms close is currently available merely because its source is unit-tested. |
| S7 for v1 | Safe sensor-less *degradation* is an automated release gate: no-HID selection, bounded recovery, no orphaned source/capture/overlay/timer, immediate sleep seal, fresh post-unlock frame, permission handling, and accurate UI copy. A visible close and physical sensor-less hardware qualification are **not** v1 pass criteria. They remain separately tracked, unverified post-v1 work. |
| M5 definition of done | Remove the requirement to call a sensor-less physical test green before v1, but require the release notes and supported-model table to mark that hardware path unverified/experimental and its close animation currently unavailable. A future close is best-effort only after trigger qualification. All other gates—including S6 fidelity, privacy, installed-app checks, Developer ID signing, notarization, Gatekeeper, immutable cask, and owner approvals—remain unchanged. |
| Appendix A decision | Prefer an honest safe degradation and fresh opening over an unverified claim that a sleep event can launch a visible close after the panel has blanked. Revisit only with physical frame/timing evidence and a supported trigger. |

Under this decision, **best-effort does not mean silently trying `willSleep`**.
Until an early supported trigger is demonstrated, the product must state that
the sensor-less close animation is unavailable in the current production path. The
existing fresh-frame post-unlock animation remains subject to normal session,
display, and Screen Recording conditions; it must not reuse a pre-sleep frame.

## Implementation and follow-up

1. The PRD, M5 plan, app mode copy, README, and release matrix reflect the
   approved contract. The idle, privacy, and resource-lifecycle invariants and
   all non-S7 release gates remain unchanged.
2. Retain deterministic tests for no-HID selection and recovery, immediate
   sleep cleanup, timer idleness, stale-callback suppression, and fresh
   post-unlock unfold. A forced-no-HID test on a sensor-equipped Mac can aid
   engineering but must be labeled a simulation, not physical qualification.
3. After access to a genuinely sensor-less Mac, measure event-to-last-visible
   frame timing, actual close visibility (if any), fresh unlock, idle cost, and
   repeated sleep/wake. Upgrade the supported-model claim only after that run.

## Approval boundary

This is a material change to the original G4/FR-11/S7 promise. Owner approval
authorized the PRD and implementation-plan revision; it did **not** declare M5
shipped, prove sensor-less behavior, authorize a push or release, or waive any
other open gate.
