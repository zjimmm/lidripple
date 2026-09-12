# lidripple Plan 2c: Metal Fold Renderer

**Goal:** Turn one immutable captured screen texture plus `FoldState.progress` into
the complete six-stage lid fold, present it in the existing overlay at native backing
resolution, and make the result deterministic enough for golden-image regression tests
and interactive scrubbing.

**Architecture:** A new `LidRippleRenderer` library depends on `LidRippleCore` and
`LidRippleCapture`. `FoldRenderer` owns immutable Metal pipelines and a one-capture
`TexturePyramid`; rendering a frame changes only a small uniform buffer and the output
target. `FoldMetalView`, an `MTKView`/`CAMetalLayer` presentation adapter, owns the
triple-buffered drawable loop. The overlay depends on the renderer and swaps its
temporary AppKit placeholder for this view. A small preview executable supplies a
synthetic checkerboard/gradient frame and progress slider without Screen Recording or
sensor access.

**Shader packaging decision:** This machine has a functional runtime Metal compiler but
does not have Xcode's optional command-line Metal Toolchain installed. The shader source
therefore ships as a Swift static string and is compiled exactly once in
`FoldRenderer.init`. This occurs during app setup, before capture or animation. The
shader entry-point names and pipeline creation are tested, and the source remains one
file so it can be moved verbatim to an ahead-of-time `.metal` resource when the optional
toolchain becomes part of the release build.

**Scope boundary:** This plan implements pixels, local preview controls, and the API M3
will call. It does not connect sensor phases to capture lifecycle, handle sleep/lock
events, or add the final menu-bar command surface. Those are M3 and M5 concerns.

**Platform:** Swift 6, macOS 14+, Metal, MetalKit, AppKit, CoreGraphics/ImageIO for test
artifacts. No third-party packages, network calls, captured-frame disk writes, or TCC
prompts.

## Requirements and decisions

| Requirement | Implementation |
|---|---|
| §9.3.1 | A pure 16×64-cell indexed mesh (17×65 vertices), bottom-hinge `v = 0`. |
| §9.3.2 | Vertex shader applies nonlinear squash and hinge perspective from tuning uniforms. |
| §9.3.3 | Six levels are generated once per source by separable Gaussian compute passes. |
| §9.3.4–6 | Fragment shader applies the climbing warm-black void, cool rim/tint/vignette, and deterministic high-frequency dither. |
| §9.4 / FR-17 | Every visual constant is supplied by `FoldTuning`; intensity continues to scale only blur, rotation, and squash. |
| §12.3 | Five native Metal golden renders use a deterministic synthetic source and approximately 2/255 tolerance. |
| §12.4 | A permission-free preview executable offers a slider and synthetic progress playback. |
| S1 | An opt-in 3456×2234 benchmark records GPU completion time and asserts <4 ms on the M1 Pro baseline. |
| S4 | The presentation view is paused while idle and encodes no frames without a source texture. |

The test output is fixed at 320×200 to keep checked-in PNGs small. Golden comparison is
performed in BGRA byte space: every channel must stay within 2/255 and mean absolute
error must not regress above 0.25/255. Cross-GPU differences outside that contract are a
real review event, not silently re-blessed output.

---

## Task 1: Renderer target, tuning contract, and mesh

- [ ] Add `LidRippleRenderer` and `LidRippleRendererTests`; make the renderer depend only
      on Core and Capture.
- [ ] Add the missing render constants to `FoldTuning`: perspective field of view and eye
      distance/offset, warm-black color, cool tint, vignette, dither amplitude, and blur
      extra-tap distance. Include them in Codable overrides and tuning tests.
- [ ] Preserve `withIntensity`'s exact three-field scaling contract.
- [ ] Add a pure `FoldMesh.make(columns:rows:)` producing normalized `(u,v)` vertices and
      counter-clockwise indexed triangles. Reject zero-sized grids.
- [ ] Test the default 17×65 vertex / 6144-index shape, all corners, bounds, winding, and
      shared row continuity.
- [ ] Run the full suite and commit.

---

## Task 2: Shader library and render uniforms

- [ ] Add one shader source with `foldVertex`, `foldFragment`, `gaussianHorizontal`, and
      `gaussianVertical` entry points.
- [ ] Define a Swift/Metal-compatible, 16-byte-aligned `FoldUniforms` layout built from
      clamped progress, viewport/source size, and every `FoldTuning` visual term.
- [ ] Vertex stage: apply `pow(v, 1 + squashGain*p)`, bottom-hinge rotation, and the
      38-degree short-focal perspective; preserve exact full-screen geometry at `p=0`.
- [ ] Fragment stage: sample fractional mip LOD plus one offset tap, then apply void,
      Gaussian rim, cool tint, vignette, and 1.5/255 high-frequency dither.
- [ ] Unit-test uniform clamping/layout and compile all four functions on the system
      Metal device. Tests skip only when Metal is genuinely unavailable.
- [ ] Run the full suite and commit.

---

## Task 3: One-time six-level Gaussian texture pyramid

- [ ] Add `TexturePyramid` with exactly `min(6, floor(log2(maxDimension))+1)` levels.
- [ ] Copy source level zero to an owned shader-readable texture; do not retain a mutable
      live capture surface as renderer working storage.
- [ ] Generate each lower level once: horizontal Gaussian/downsample into a transient
      intermediate, then vertical Gaussian/downsample into the destination mip.
- [ ] Accept BGRA8 captured textures, preserve dimensions, and expose the immutable
      mipmapped texture only after its command buffer completes successfully.
- [ ] Tests upload impulses and constant colors, then assert energy symmetry, constant
      preservation, level dimensions, and that rendering frames does not regenerate the
      pyramid.
- [ ] Run the full suite and commit.

---

## Task 4: Offscreen `FoldRenderer`

- [ ] `FoldRenderer.init(device:tuning:)` compiles the shader library once, creates all
      pipelines, mesh buffers, depth/blend state if needed, and a triple-buffered uniform
      ring.
- [ ] `setSource(_:)` builds and atomically replaces one `TexturePyramid`; a test-only
      texture overload keeps golden tests independent of ScreenCaptureKit/TCC.
- [ ] `render(progress:to:commandBuffer:)` is stateless per frame, draws into any
      `.bgra8Unorm` target, and returns without encoding when no source is installed.
- [ ] Clamp geometry progress to the driver's `[0, 1.06]` range while allowing values
      above 1 to produce extra void.
- [ ] Add deterministic offscreen tests for no-source behavior, p=0 source fidelity,
      increasing occupied-void area, hinge anchoring, and source replacement.
- [ ] Run the full suite and commit.

---

## Task 5: Golden-image regression harness

- [ ] Generate a known checkerboard-plus-RGB-gradient source entirely in memory.
- [ ] Render at `p = 0, 0.25, 0.5, 0.75, 1.0`, wait for GPU completion, and compare to
      checked-in PNG references bundled with the renderer test target.
- [ ] Enforce max per-channel error <=2 and mean absolute error <=0.25 in 8-bit space;
      write no files during the normal test path.
- [ ] Provide an explicitly invoked `LIDRIPPLE_RECORD_GOLDENS=1` maintenance path that
      writes only into a caller-supplied temporary/artifact directory, never over the
      checked-in references automatically.
- [ ] Render and visually inspect all five references before committing them.
- [ ] Run the full suite and commit.

---

## Task 6: Native presentation view and overlay adoption

- [ ] Add `FoldMetalView: MTKView` backed by `CAMetalLayer`, with native drawable size,
      `.bgra8Unorm`, vsync enabled, and `maximumDrawableCount = 3`.
- [ ] Expose main-actor `setSource(_:)`, `update(_:)`, and `clearSource()` methods. Idle
      and armed states pause drawing; folding/unfolding/sealed states draw the newest
      progress without creating an independent animation clock.
- [ ] Replace `FoldPlaceholderView` in `OverlayPresenter`; retain exactly one window and
      preserve its existing lifecycle and capture-exclusion ID.
- [ ] Keep a renderer/device injection seam so overlay tests remain deterministic and do
      not require a drawable from WindowServer.
- [ ] Test paused/active transitions, progress forwarding, native-scale resizing, and
      unchanged window ordering behavior.
- [ ] Run the full suite and commit.

---

## Task 7: Permission-free scrub preview and performance probe

- [ ] Add `lidripple-preview`, a development executable that creates only the built-in
      overlay, uploads the deterministic synthetic source, and offers a compact slider
      plus play/reverse controls for `p = 0...1.06`.
- [ ] Keep preview independent of ScreenCaptureKit, sensor hardware, and permission
      state; quitting always tears down the overlay.
- [ ] Add an opt-in `LIDRIPPLE_RENDER_BENCHMARK=1` GPU benchmark at 3456×2234. Record
      command-buffer GPU start/end time across warm and measured frames; assert the
      design's <4 ms target only when the environment identifies the M1 Pro baseline,
      while reporting measurements on other GPUs without pretending equivalence.
- [ ] Run ordinary build/tests first, then run preview and benchmark only with local GPU
      access. Record device, resolution, median, p95, and whether the S1 baseline applies.
- [ ] Commit and perform a whole-branch review.

---

## Definition of done

- [ ] Ordinary `swift build` and `swift test` pass without capture permission or sensor
      hardware.
- [ ] One captured texture produces one six-level Gaussian pyramid; frame rendering does
      not rebuild it.
- [ ] All six specified render stages are present and driven only by progress/tuning.
- [ ] `p=0` is a faithful full-screen source; the bottom hinge remains fixed throughout.
- [ ] The renderer accepts the immutable `CapturedFrame` delivered by Plan 2b.
- [ ] Overlay output uses a native-scale, vsynced, triple-buffered `CAMetalLayer` and does
      no GPU work in idle/armed phases.
- [ ] Five golden PNGs pass the stated numerical thresholds and have been visually
      inspected.
- [ ] Scrubbing works without Screen Recording permission or physical lid motion.
- [ ] Performance is measured honestly against the named hardware rather than claimed
      from a unit test or a different GPU.
- [ ] No captured user content is written to disk, logged, or sent over a network.

## What M3 covers

M3 wires driver phases to `CaptureCoordinator`, `FoldMetalView`, and the overlay:
speculative warm-up in `.armed`, freeze at `.folding`, clean reversal, sealed/sleep
teardown, post-unlock scripted unfold, display changes, and the remaining lifecycle edge
cases. Plan 2c deliberately supplies those APIs without owning their orchestration.
