# Contributing to LidRipple

LidRipple is an MIT-licensed macOS app. Keep the consumer experience simple:
Fold, Ripple, sensible defaults, and no calibration exercise.

## Build and test

Use macOS 14 or later and a Swift 6-capable Xcode toolchain. Full Xcode is needed
for release packaging. From a fresh clone:

```sh
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
scripts/build-app.sh --adhoc-sign --output dist/local
```

The local bundle is `dist/local/LidRipple.app`. An ad-hoc build is not a notarized
release and may need explicit approval in macOS Privacy & Security. Screen Recording
is required for desktop effects; physical tracking needs a readable lid-angle sensor.
Do not run multiple copies alongside an installed release.

## Changes and reports

Open an issue before proposing broad new features. Include your Mac model, macOS
version, app version, effect, and whether the issue followed sleep or unlock.
Do not attach personal desktop captures, credentials, or unredacted logs.

Keep state-machine tests deterministic. Add regression coverage for motion, capture,
and lock-state changes. Never bypass session restrictions, reuse pre-lock captures,
or weaken system security to make an animation work.

Submit focused pull requests with test results. Contributions must be compatible
with the repository's MIT license. Identify the provenance and license of any assets.
Do not redistribute reference footage without permission.

Release readiness is tracked in
[the checklist](docs/verification/2026-09-15-release-checklist.md).
