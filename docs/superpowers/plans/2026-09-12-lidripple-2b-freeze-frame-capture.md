# lidripple Plan 2b: Freeze-Frame Capture

**Goal:** Add a ScreenCaptureKit pipeline that warms at low frame rate for the
built-in display, excludes lidripple's overlay window, freezes the newest complete
frame into a durable Metal texture, and tears the stream down immediately.

**Architecture:** A new `LidRippleCapture` library owns capture and texture bridging.
`CaptureCoordinator` is an actor whose public lifecycle is `warm`, `freeze`, and
`reset`; an injected session factory makes re-entrancy and failure behavior testable
without Screen Recording permission. `ScreenCaptureSession` is the production backend.
It builds an `SCContentFilter` for one `CGDirectDisplayID`, requires the requested
overlay `CGWindowID` to be present in the exclusion list, receives only complete BGRA
screen frames, and stores the newest `CapturedFrame`. `CapturedFrame` retains the
`CVMetalTexture` backing object as well as the `MTLTexture`, so the frozen IOSurface
cannot disappear after the stream stops.

**Scope boundary:** This plan produces a frozen texture but does not render it and does
not wire capture to `AppDelegate`; Plan 2c consumes it in the Metal renderer, and M3
wires phase transitions end to end. Normal builds and tests never request Screen
Recording permission. One opt-in smoke test is the only permission-triggering path.

**Platform:** Swift 6, macOS 14+, ScreenCaptureKit, CoreMedia, CoreVideo, CoreGraphics,
Metal. No third-party packages, disk writes, network calls, audio capture, or external
display capture.

## Requirements and decisions

| Requirement | Implementation |
|---|---|
| FR-1 / G6 | No stream exists in `idle`; normal tests do not touch TCC. |
| FR-2 | `warm` starts a 10 fps stream with queue depth 1. |
| FR-3 | `freeze` retains the newest complete frame and awaits stream shutdown. |
| FR-10 | A later caller can `reset`, `warm`, and freeze a fresh post-unlock frame. |
| FR-13 | The caller supplies the built-in `CGDirectDisplayID`; no fallback display is guessed. |
| §10.1 | `reset` is idempotent and always tears down an in-flight stream. |
| §10.6 | A requested overlay window must be found and excluded or warm-up fails closed. |
| §10.8 | Actor state plus idempotent methods prevent duplicate streams and orphaned frames. |
| §11 | Captured content stays in IOSurface/Metal memory and is never encoded or written. |

The 10 fps warm rate is deliberately provisional. It is fast enough to keep the newest
frame within 100 ms while being much cheaper than display rate; M4 tunes the warm-band
latency/privacy-indicator tradeoff with measurements.

## File structure

| File | Responsibility |
|---|---|
| `Package.swift` | Add `LidRippleCapture` and its test target. |
| `Sources/LidRippleCapture/CaptureError.swift` | Stable, testable capture failures. |
| `Sources/LidRippleCapture/CaptureConfiguration.swift` | Native-pixel BGRA stream configuration. |
| `Sources/LidRippleCapture/CapturedFrame.swift` | Durable CVPixelBuffer-to-Metal bridge. |
| `Sources/LidRippleCapture/CaptureSession.swift` | Internal session seam and production ScreenCaptureKit backend. |
| `Sources/LidRippleCapture/CaptureCoordinator.swift` | Idempotent actor lifecycle. |
| `Sources/LidRippleOverlay/BuiltInDisplay.swift` | Expose the selected display ID as well as its `NSScreen`. |
| `Sources/LidRippleOverlay/OverlayPresenter.swift` | Expose the owned overlay window ID for exclusion. |
| `Tests/LidRippleCaptureTests/*` | Configuration, texture lifetime, lifecycle, and opt-in smoke tests. |

---

## Task 1: Capture target IDs and package target

- [ ] Add `.library(name: "LidRippleCapture", targets: ["LidRippleCapture"])`.
- [ ] Add a dependency-free local target (system frameworks only) and a test target
      depending on both `LidRippleCapture` and `LidRippleOverlay` for the smoke path.
- [ ] Add `BuiltInDisplay.displayID(for:)` and `BuiltInDisplay.displayID()` so the same
      device-description conversion used by `screen()` is reusable and unit-testable.
- [ ] Add `OverlayPresenter.windowID: CGWindowID`; keep the actual window private.
- [ ] Tests assert the selected display ID is built-in when present and the presenter's
      window ID is nonzero on supported hardware.
- [ ] Run the full suite and commit.

`LidRippleCapture` may import `Foundation`, `CoreGraphics`, `CoreMedia`, `CoreVideo`,
`Metal`, and `ScreenCaptureKit`. It must not import any other lidripple target. The
coordinator accepts numeric display/window IDs, which keeps capture independent of AppKit
window ownership.

---

## Task 2: Native-pixel stream configuration

- [ ] Add `CaptureConfiguration.make(contentRect:pointPixelScale:)` returning an
      `SCStreamConfiguration`.
- [ ] Compute dimensions as the rounded product of the filter's point-space content
      rectangle and `pointPixelScale`, clamped to at least one pixel.
- [ ] Configure:
  - `minimumFrameInterval = CMTime(value: 1, timescale: 10)`;
  - `queueDepth = 1`;
  - `pixelFormat = kCVPixelFormatType_32BGRA`;
  - `showsCursor = false`;
  - `capturesAudio = false`;
  - `colorSpaceName = CGColorSpace.sRGB`.
- [ ] Unit-test 1× and Retina scaling, fractional rounding, the 1-pixel clamp, and every
      static stream property. No test may enumerate shareable content.
- [ ] Run the full suite and commit.

The filter's `contentRect` and `pointPixelScale` are the authority rather than
`NSScreen.backingScaleFactor`; this keeps ScreenCaptureKit's requested surface aligned
with the actual filtered content.

---

## Task 3: Durable captured Metal frame

- [ ] Add immutable `CapturedFrame`, marked `@unchecked Sendable` with a documented
      justification: Metal textures are designed for cross-queue command encoding and
      all exposed state is read-only.
- [ ] Store public `texture`, `width`, and `height` plus a private strong reference to
      the originating `CVMetalTexture`.
- [ ] Add a factory that uses `CVMetalTextureCacheCreateTextureFromImage` with
      `.bgra8Unorm` and plane 0. It returns nil for zero-sized or non-Metal-compatible
      buffers rather than trapping.
- [ ] Tests create an IOSurface-backed, Metal-compatible BGRA `CVPixelBuffer`, bridge it,
      release the local pixel-buffer reference, and assert the texture remains valid at
      the expected dimensions and format.
- [ ] A second test rejects an unsupported pixel format.
- [ ] Run the full suite and commit.

Retaining only the `MTLTexture` is not sufficient proof of lifetime. The wrapper object
returned by CoreVideo is retained explicitly for the complete frozen-frame lifetime.

---

## Task 4: ScreenCaptureKit session

- [ ] Define an internal `CaptureSession: Sendable` protocol with async `start()`,
      `stop()`, and `latestFrame()` operations.
- [ ] `ScreenCaptureSession.make(displayID:excludingWindowID:device:)` obtains
      `SCShareableContent.current`, selects exactly the requested display, and locates
      exactly the requested overlay window.
- [ ] If either ID is missing, throw `.displayNotFound` or `.excludedWindowNotFound`.
      Do not silently capture another display or omit the exclusion.
- [ ] Build `SCContentFilter(display:excludingWindows:)`, then derive Task 2's
      configuration from `filter.contentRect` and `filter.pointPixelScale`.
- [ ] Add one `.screen` output on a private serial queue and start the stream.
- [ ] Accept only valid sample buffers whose frame attachment status is `.complete`.
      Obtain `CVImageBuffer`, bridge it through the session's texture cache, and replace
      the latest frame under a lock. Queue depth 1 means old speculative frames are
      released immediately.
- [ ] `stop()` is idempotent. It awaits `SCStream.stopCapture()`, removes the output, and
      clears stream ownership even when stop reports an error.
- [ ] Delegate stop errors are recorded and surfaced by the next lifecycle operation;
      they must not orphan a stream.
- [ ] Unit-test attachment-status parsing as a pure helper. Production construction is
      compile-tested here; live capture belongs to Task 6.
- [ ] Run the full suite and commit.

---

## Task 5: Idempotent coordinator lifecycle

- [ ] Add public actor `CaptureCoordinator` with state `.idle`, `.warming`, `.frozen`.
- [ ] The default initializer uses `MTLCreateSystemDefaultDevice`; expose
      `.metalUnavailable` if no device exists.
- [ ] `warm(displayID:excludingWindowID:)`:
  - returns immediately while already warming for the same IDs;
  - rejects conflicting IDs rather than running two streams;
  - discards an old frozen frame before a new cycle;
  - publishes `.warming` before its first suspension point to close the actor
    re-entrancy window;
  - returns to `.idle` on construction/start failure.
- [ ] `freeze()` requires `.warming`, snapshots the newest frame, awaits stop, then
      publishes `.frozen`. If no complete frame arrived, return to `.idle` and throw
      `.noFrameAvailable`.
- [ ] `reset()` stops any session, clears frozen content, and is safe from every state.
- [ ] Inject a session factory internally. Actor-backed fakes test duplicate warm calls,
      conflicting targets, freeze-before-warm, no-frame failure, successful retention,
      repeated reset, and restart after reset without TCC.
- [ ] Store the in-progress warm task plus a monotonically increasing generation token.
      `freeze` awaits the same task; `reset` invalidates the generation and stops any
      session that finishes afterward. This closes actor re-entrancy races while content
      enumeration or stream startup is suspended.
- [ ] Run the full suite and commit.

---

## Task 6: Opt-in real capture smoke test

- [ ] Add one async test gated by `LIDRIPPLE_CAPTURE_SMOKE=1`. With the variable absent,
      it returns before enumerating `SCShareableContent`, so normal `swift test` never
      prompts.
- [ ] Before the permission-triggering call, print that lidripple will capture only the
      built-in display for under one second, keep one GPU frame in memory, and write
      nothing to disk or network.
- [ ] Create an `OverlayPresenter`, obtain its window ID, warm capture for up to one
      second, freeze, and assert a nonzero BGRA texture matching the built-in display's
      native pixel dimensions.
- [ ] Reset and assert the coordinator returns to idle.
- [ ] Run ordinary `swift build` and `swift test` first.
- [ ] Only with the user's explicit consent, run:

```bash
LIDRIPPLE_CAPTURE_SMOKE=1 swift test --filter realBuiltInDisplayCapture
```

- [ ] Report whether permission was already granted, prompted and granted, denied, or
      unavailable. Never claim live capture passed based only on the ordinary suite.

---

## Definition of done

- [ ] Ordinary `swift build` and `swift test` pass without a permission prompt.
- [ ] `LidRippleCapture` has no dependency on sensor, driver, trace, or app targets.
- [ ] No capture begins until `warm` is called; one stream maximum exists at a time.
- [ ] Only the requested built-in display is selected.
- [ ] The overlay window is present in `SCContentFilter`'s exclusion list, or warm-up
      fails closed.
- [ ] Only complete BGRA video frames can become frozen textures.
- [ ] Frozen texture lifetime survives stream teardown.
- [ ] Reset and error paths release the stream and frame.
- [ ] No audio, cursor, file output, network access, or automatic TCC prompt exists.
- [ ] The opt-in hardware smoke result is reported honestly.

## What Plan 2c covers

The Metal renderer and its tests: mesh warp, perspective hinge rotation, non-rigid
squash, one-time six-level mip generation, progressive blur, void horizon, rim light,
`MTKView` presentation, scrub mode, and golden-image/reference checks. It consumes the
immutable `CapturedFrame` produced here.
