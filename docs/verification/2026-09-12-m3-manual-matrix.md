# M3 integration verification matrix

Date: 2026-09-12  
Build host: Mac16,12 / Apple M4 / macOS 26 SDK toolchain

Automated evidence is reproducible with:

```sh
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
```

The physical checks below require a person to move the lid or change the logged-in
macOS session. They were not fabricated during the automated implementation session.
They remain the pre-release acceptance matrix for M5.

| Scenario | Automated coverage | Physical status |
|---|---|---|
| Unlocked slow close/open | canonical trace through driver, capture, and output fakes | Not run; human lid motion required |
| Reversal at 25%, 50%, 90% | reversal and close-reopen-close traces; generation tests | Not run; human lid motion required |
| Full close / sleep race | hard-seal and capture-reset tests | Not run; would suspend this session |
| Locked close and fresh unlock | lock-phase, fresh capture, stale-source, and 620 ms tests | Not run; user session change required |
| Capture denial fallback | warm failure produces generated warm-black alpha reveal | Not run; changing TCC state deferred to release acceptance |
| Fullscreen app / Spaces | shielding-window contract tests | Not run; interactive Space change required |
| Built-in plus external / clamshell | built-in-only target and physical-seal reopen tests | Not run; external display and lid motion required |
| Display attach/detach mid-fold | same-ID resize, ID replacement, nil/return, authority tests | Not run; external display and lid motion required |
| Fast user switching | session resignation resets and blocks display recovery | Not run; second account/session required |
| Low Power / thermal pressure | 1-tap/3-tap mode and 60 Hz clock tests | Not run; OS power-state interaction required |
| Sensor service loss/recovery | consecutive-failure gate, bounded retries, cancellation, fallback handoff | Fault injected in tests; physical service loss not available |
| DRM/protected content | capture path treats pixel content opaquely; black textures render unchanged | Not run with protected media; behavior delegated to ScreenCaptureKit |

No captured pixels are written by these tests or by the runtime. The opt-in real
ScreenCaptureKit smoke test remains gated by `LIDRIPPLE_CAPTURE_SMOKE=1` because it
requires Screen Recording permission and a live WindowServer session.

The opt-in smoke was run on this host and passed: the built-in display was captured for
under one second, one GPU-backed frame was retained in memory, and the stream stopped
without writing content to disk.
