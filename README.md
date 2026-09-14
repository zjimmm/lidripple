# LidRipple

> **Pre-release status:** implementation is in progress. The frame-matched M4 Duo
> comparison GIF, notarized v1.0.0 artifact, Homebrew cask, and v1 sensor-less
> safety acceptance (S7) are not yet available. This repository does not claim those
> release gates have passed. Physical qualification on a genuinely sensor-less Mac
> is separately tracked after v1.

lidripple is a native macOS menu-bar agent that turns closing a MacBook lid into a
screen-fold animation. A physical lid-angle sensor drives the effect when the hardware
exposes one. Without a validated sensor, the app is designed to seal safely on sleep
and can provide a fresh scripted unfold after unlock when the session and Screen
Recording permission allow it. Both modes use the same Swift state machine,
ScreenCaptureKit freeze frame, and Metal renderer; a sensor-less close animation is not
currently available.

After unlock, a sensor-equipped Mac holds the fresh-frame opening reveal to the
measured lid angle and smooths its whole-degree steps, with a 620 ms reveal curve and a
bounded timeout if readings stall. The first fresh angle places the reveal at the
current lid pose; if the lid is already fully open, the late reveal is skipped.
Sensor-less Macs use the timed reveal. The app cannot show the part of an opening
that happens before macOS unlocks the desktop.

The checked-in [M4 evidence](docs/fidelity/README.md) records reference provenance,
timing analysis, local artifact hashes, and the remaining acceptance gaps. The required
side-by-side artifact will be placed at `docs/fidelity/duo-comparison.gif` only after a
lawfully redistributable reference is available and the runtime-timed result passes
human fidelity review. It is intentionally not represented by a placeholder.

## Requirements and compatibility

- macOS 14 Sonoma or later
- A built-in display
- Screen Recording permission for the fold effect
- Apple Silicon or Intel (the universal artifact remains a release verification gate)

| Mac | Input mode | Current status and caveat |
|---|---|---|
| MacBook exposing Apple HID vendor `0x05AC`, product `0x8104` | Lid angle sensor | Auto-detected. The observed report changes in whole-degree steps and the current `rawToDegrees = 1.0` scale still needs a physical sweep before precision claims. |
| MacBook without that HID endpoint | Sensor-less fallback (experimental/unverified on real no-HID hardware) | Safe sleep seal and fresh post-unlock scripted unfold when conditions allow. No visible close animation is currently available; physical no-HID qualification is post-v1 work. |
| Desktop Mac or external-display-only setup | Input unavailable | The effect represents the built-in panel, so no overlay is presented. |

Sensor-less fallback is not angle tracking. A clamshell close that does not produce a
sleep event may be undetectable, and physical mid-close reversal is unavailable in this
mode. The current `willSleep` handler immediately seals and releases capture for safety;
it does not start the unit-tested, approximately 550 ms close program. A visible close
would be best-effort only after an early supported trigger is proven while the built-in
panel can still display frames. No such production trigger has been demonstrated.
The v1 S7 gate covers safe automated degradation, not a visible close or physical
qualification on a no-HID Mac; that hardware path remains experimental and unverified.

## Controls

After an authorized unlock, fresh lid sampling runs alongside fresh screen capture.
A native frosted cover in the capture-excluded overlay obscures the preparation
gap without storing an old desktop image. It clears over 160 ms as the measured
opening frame appears, has a 550 ms safety timeout, and is removed immediately
on session restrictions or abort. This experimental handoff cannot cover system
frames shown before the app receives unlock notification.
Both effects preserve full measured opening progress with display-rate smoothing
of whole-degree sensor steps. There is no separate entrance ramp or depth cap.
Fresh sensor samples keep the opening pose active even through a slow opening or
pause; the safety timeout releases the image only after sensor updates stop.
The opening effect starts at a recent measured pose. If preparation takes over
300 ms, or no fresh sensor pose arrives within the short first-sample wait, the
decorative reveal is skipped instead of folding an already-visible desktop again.
No pre-lock image or black cover is retained. macOS can expose the desktop before
the app receives unlock notification, so this reduces late replay rather than
guaranteeing a flash-free wake.

The menu-bar UI exposes Enable, Effect (Fold or Ripple), Launch at Login, the
active input mode, Screen Recording state, a permission-free effect preview, Check for
Updates, and Quit. Fold remains the default. Ripple is a full-screen liquid refraction
originating at the bottom hinge: its waves follow progress on closing and opening,
hold with the lid, and fade to the same sealed endpoint. The selection is saved.
Both effects use curated strength defaults; the former intensity slider is no longer
shown, and its saved value resets to full strength at app initialization.

Preview Effect shows a compact, automatically looping MacBook illustration with
procedural landscape artwork. Switch between Fold and Ripple to see an approximation
of each effect. It never captures or covers the desktop, and live lid tracking continues.
Closing the preview stops its animation; sleep and session restrictions close it too.
“Check for Updates” opens the GitHub Releases page in the default browser; the app does
not make an update request itself.

## Privacy and permissions

lidripple needs **Screen Recording** because ScreenCaptureKit must briefly capture the
built-in display to freeze the visible desktop before the fold. The overlay is excluded
from capture. One frame is retained ephemerally for GPU rendering, then released.

- No Accessibility permission
- No Input Monitoring permission
- No app-owned network connection
- No telemetry or analytics
- No captured pixels written to disk, preferences, diagnostics, or logs
- No App Sandbox entitlement; distribution therefore uses Developer ID rather than the
  Mac App Store

The first-run flow explains this before invoking the system permission request. Choosing
Not Now leaves the menu available. If permission is denied, choose **Screen Recording:
Needs Permission** in the menu and enable lidripple in **System Settings → Privacy &
Security → Screen & System Audio Recording**, then reactivate the app.

Protected or DRM video may produce a black captured region. lidripple preserves that
black result and never tries to bypass content protection.

## Install

There is no published release yet. When the v1.0.0 gates pass, installation will be:

1. Download the notarized `lidripple-1.0.0.dmg` and its SHA-256 file from the matching
   GitHub Release.
2. Verify the checksum, open the DMG, and drag `LidRipple.app` to Applications.
3. Launch the app and follow its Screen Recording explanation.

A Homebrew cask will be added only after it can name that exact immutable DMG and exact
SHA-256; this project never uses `sha256 :no_check`.

To uninstall, turn off Launch at Login in lidripple, quit it, and move
`/Applications/LidRipple.app` to Trash. Remove the app's preferences only if you also
want to reset onboarding and controls:

```sh
defaults delete com.lidripple.app
```

## How the fold works

The input angle is filtered and mapped through hysteretic phases (`idle → armed →
folding → sealed`). During folding, target progress comes from the angle interval and a
damped spring adds momentum while remaining reversible. The renderer transforms a
subdivided panel around its bottom hinge. A vertical coordinate `v` is compressed as
`v^(1 + squash × progress³)`, then perspective-rotated; delaying the geometry keeps
content visible through mid-close. A scene-derived, spatially uniform color fills
the exposed background without repeating the frozen desktop. Position-dependent blur softens the panel, a narrow hinge
shadow and rim give it depth, and only the final seal fades to near-black. Opening runs
the same motion backward when angle samples are available, or performs a fresh scripted
reveal after unlock.

See the [design specification](docs/superpowers/specs/2026-09-12-lidripple-design.md)
and [sensor evidence](docs/sensor.md) for the full contracts and known hardware caveats.
M3 lifecycle evidence is recorded in the
[integration matrix](docs/verification/2026-09-12-m3-manual-matrix.md).
The [M4 fidelity report](docs/fidelity/report.json) records measurements from before
the 2026-09-13 retained-content renderer revision; it must be rerun for this candidate.
The comparison artifact remains a release gate until it is lawful to publish and accepted.

## Build and test

Xcode's macOS 14 SDK and the Swift 6 toolchain are required.

```sh
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
```

The repository includes the original `Packaging/AppIcon.icns`. Assemble an ad-hoc
universal app with:

```sh
scripts/build-app.sh --adhoc-sign
```

For repeated local builds on a Mac with a code-signing certificate, use
`scripts/build-app.sh --sign-identity "<identity hash>"` instead. Find the hash with
`security find-identity -v -p codesigning`. Certificate signing keeps a stable
Screen Recording permission identity across rebuilds; switching from an ad-hoc
build still requires granting permission to the newly signed app once.

Developer ID signing, notarization, artifact verification, and cask publication are
maintainer procedures documented in [docs/releasing.md](docs/releasing.md). They require
real Apple credentials and cannot be replaced by CI or an ad-hoc signature.

## Troubleshooting

- **No animation:** confirm Enable is checked, the built-in display is active, and the
  menu does not report missing Screen Recording permission.
- **Input remains paused immediately after launch:** on macOS builds that omit the
  session lock-state key, open lidripple's status menu once after reaching the desktop.
  The app waits for that direct interaction rather than guessing whether a locked
  session is safe to capture. Automatic startup in this case is still a release gate.
- **Permission remains denied after changing Settings:** reactivate or relaunch
  lidripple so it refreshes TCC state.
- **Sensor-less fallback selected:** this is expected when the HID endpoint is absent or
  recovery is exhausted. Close animation is currently unavailable in this mode; a
  fresh unfold after unlock still depends on an eligible session and Screen Recording
  permission.
- **Black protected content:** this is expected DRM behavior, not a capture bypass bug.
- **No Dock icon:** intentional. `LSUIElement` makes lidripple a menu-bar agent.
- **Sensor motion looks coarse:** current hardware evidence is one-degree quantized and
  the raw scale remains provisional; include model, macOS version, and a recorded trace
  in a bug report.

## License and support

lidripple is available under the [MIT License](LICENSE).

If the GitHub Sponsors profile is active, you can [sponsor zjimmm on
GitHub](https://github.com/sponsors/zjimmm). Sponsors-profile activation is a publishing
gate and has not been verified by this repository alone.
