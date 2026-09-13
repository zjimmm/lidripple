# lidripple Plan M4: Duo Fidelity

**Goal:** Tune lidripple against a lawfully redistributable recording of the real iPhone
Duo transition until S6 holds, then commit a reproducible, frame-matched comparison GIF
that lets a reviewer judge blur onset, void climb, duration, geometry, and finish.

**Definition of S6:** Numerical measurements are guardrails, not a substitute for visual
judgment. S6 requires all three objective tolerances below, a generated side-by-side GIF,
and explicit human approval of the complete motion. A passing metric alone is not S6.

**Current baseline:** The renderer already exposes every visual constant through
`FoldTuning`, supports JSON hot reload in `lidripple-preview`, renders deterministic
offscreen frames, and protects five progress goldens. M4 adds an independent fidelity
harness; it does not replace the existing synthetic goldens or turn copyrighted media
into an ordinary test dependency.

**Scope boundary:** M4 tunes visual and temporal fidelity and produces the S6 artifact.
It may change `FoldTuning` defaults and shader math when evidence calls for it, but must
preserve FR-17's exact intensity contract and M3 lifecycle/resource guarantees. Menu,
fallback input, onboarding, distribution, and packaging remain M5.

## Reference and rights gate

The comparison GIF is a derivative redistribution of its reference frames. Before any
reference or GIF is committed, add `References/Duo/reference.json` containing:

- stable source URL, title, creator/publisher, acquisition date, and exact clip timecode;
- the original file's SHA-256, frame rate/time base, dimensions, color space, and any
  crop/perspective-correction coordinates;
- a SPDX license identifier when applicable, plus the URL or checked-in permission text
  that explicitly permits redistribution and derivative comparison media;
- attribution text required in the GIF and repository documentation.

Apple marketing footage, social reposts, and news embeds are not assumed reusable merely
because they are public. Prefer a project-owned physical recording; otherwise obtain
written permission. Until this gate is satisfied, local footage may be used for private
tuning but neither it nor a derived GIF may be committed, and S6 remains incomplete.
The generator validates the manifest and source hash before processing.

## Frame alignment contract

1. Decode reference frames at their presentation timestamps with AVFoundation; preserve
   the source time base until final GIF resampling.
2. Perspective-correct the four recorded display corners into a rectangular panel crop
   using manifest coordinates, then crop both reference and candidate to the active
   display aperture. Do not align against phone bezel, reflections, or camera movement.
3. Mark two immutable temporal anchors in the manifest: `foldStart`, the last frame
   before the first repeatable geometry change, and `foldComplete`, the first frame after
   which panel luminance/geometry is stable for three source frames. Record who selected
   them and why.
4. Define normalized time `q = (t - foldStart) / (foldComplete - foldStart)`. Candidate
   frames use the exact progress curve and duration under evaluation, sampled at each
   reference `q`; nearest-frame selection is forbidden when timestamp interpolation is
   available.
5. Estimate and record one spatial transform at `foldStart`; hold it constant for the
   entire clip. Any per-frame optical alignment would hide real geometry differences.
6. Emit an alignment contact sheet at `q = 0, .125, .25, .375, .5, .625, .75, .875, 1`
   before tuning. Human review must confirm matching orientation, hinge edge, crop, and
   color-transfer assumptions.

## Measurable parity gates

All metrics operate in linear-light luminance on the perspective-corrected active panel,
with a manifest mask excluding glare/occlusion. Thresholds are fixed before tuning:

| Signal | Measurement | S6 tolerance |
|---|---|---|
| Total duration | `foldComplete - foldStart` for reference versus candidate | absolute error <= one source frame (or 16.7 ms, whichever is larger) |
| Void climb | per-frame normalized `v` of the strongest sustained dark-horizon boundary, measured at the nine aligned `q` samples | mean absolute error <= 0.04 panel height and maximum <= 0.08 |
| Blur onset/shape | Sobel edge-energy retention versus `q=0`, measured separately in lower/middle/upper thirds after removing the void mask | onset (first crossing below 90%) within 0.08 normalized time in every valid band; curve MAE <= 0.10 |

The report also records, without automatic pass/fail, panel silhouette IoU, rim peak
position/intensity, warm-black RGB, and end-frame residual luminance. These diagnostics
guide tuning and make regressions visible, while final geometry/rim/color approval stays
human because camera footage makes universal numeric thresholds misleading.

## Planned artifacts

| Path | Responsibility |
|---|---|
| `Sources/LidRippleFidelity/*` | Manifest validation, decoding/alignment, measurements, reports, and GIF composition |
| `Sources/lidripple-fidelity/main.swift` | Reproducible `analyze`, `contact-sheet`, and `compare-gif` CLI |
| `Tests/LidRippleFidelityTests/*` | Synthetic alignment/metric/GIF/manifest regression tests |
| `References/Duo/reference.json` | Provenance, rights, hashes, anchors, crop, mask, and attribution |
| `References/Duo/source.*` | Minimal approved reference clip, only when redistribution rights are proven |
| `docs/fidelity/tuning.json` | Machine-readable approved values and evidence metadata |
| `docs/fidelity/report.json` | Tool version, inputs, metrics, pass/fail, and output hashes |
| `docs/fidelity/alignment-contact-sheet.png` | Reviewable nine-frame alignment proof |
| `docs/fidelity/duo-comparison.gif` | Final frame-matched reference/candidate comparison required by S6 |
| `docs/fidelity/README.md` | Exact reproduction command, provenance, device/toolchain, and approval record |

## Task 1: Reference intake and deterministic manifest

- [ ] Obtain a project-owned recording or explicit redistribution/derivative permission;
      trim it to the minimum transition clip without transcoding the archival input.
- [ ] Add a strict `ReferenceManifest` decoder and validator. Reject missing rights,
      hash mismatches, invalid timecodes/corners, unsupported color metadata, or an empty
      measurement mask.
- [ ] Record the two temporal anchors and four display corners, then generate the
      nine-frame alignment contact sheet with the single fixed transform.
- [ ] Add synthetic fixtures proving perspective correction, timestamp interpolation,
      anchor normalization, hash validation, and deterministic crop/mask behavior.
- [ ] Have a human approve the contact sheet before metrics or tuning begin.

## Task 2: Reproducible fidelity renderer and CLI

- [ ] Add `LidRippleFidelity`, `lidripple-fidelity`, and tests. Use AVFoundation/CoreImage
      for reference decoding/correction and the existing Metal renderer for candidates;
      add only the narrow public offscreen texture/frame API the tool needs.
- [ ] Extract the corrected `foldStart` panel image as the candidate source so both sides
      share content. Keep this intermediate in memory unless its license permits commit.
- [ ] Render candidate frames at the reference presentation timestamps, with an explicit
      tuning JSON and duration/curve; record GPU, OS/toolchain, renderer revision, source
      hash, manifest hash, and tuning hash in `report.json`.
- [ ] Make commands fail rather than silently fall back when frames, Metal, rights
      metadata, anchors, or color conversion are unavailable. The normal app remains
      independent of AVFoundation fidelity tooling.
- [ ] Test deterministic frame count/timestamps/pixels on generated clips and confirm the
      tool never prompts for Screen Recording or writes captured desktop content.

## Task 3: Metrics and honest pass/fail reporting

- [ ] Implement linear-light conversion, fixed masks, dark-horizon extraction, per-band
      Sobel edge energy, and duration calculation exactly as specified above.
- [ ] Emit per-frame CSV/JSON detail plus aggregate tolerances. Include diagnostic
      overlays showing the detected horizon and blur bands so bad segmentation is
      reviewable rather than hidden in one score.
- [ ] Build analytic synthetic clips with known horizon speeds, blur kernels, offsets,
      durations, masks, and noise; assert values and pass/fail boundaries, including
      exactly-on-threshold cases.
- [ ] Reject comparisons when too little valid texture remains for blur measurement or
      when horizon confidence is insufficient. Do not coerce missing evidence to zero.

## Task 4: Evidence-driven tuning loop

- [ ] Establish a baseline report before changing defaults. Tune via
      `LIDRIPPLE_TUNING_FILE`/`docs/fidelity/tuning.json`, changing one family at a time:
      duration/curve, geometry/camera, blur, void, then rim/color/finish.
- [ ] Promote approved values into `FoldTuning.default`; every new constant must live in
      `FoldTuning`, be Codable/hot-reloadable, and have a documented visual role. Remove
      superseded shader literals instead of layering unexplained correction factors.
- [ ] Preserve thresholds, spring behavior, resource ownership, reduced-quality cadence,
      and `withIntensity` scaling of exactly blur radius, rotation, and squash gain.
- [ ] After each candidate, run driver/integration tests plus the metric report. Stop
      tuning to a faulty metric whenever its diagnostic overlay visibly disagrees with
      the frame.
- [ ] Record the baseline, accepted tuning, rejected alternatives, all three required
      measurements, and the reviewer-visible reason for the final choice.

## Task 5: Golden update and comparison GIF

- [ ] Treat existing synthetic goldens as renderer-regression evidence, not Duo-fidelity
      evidence. Once final defaults are approved, regenerate them exactly once through
      the existing explicit `LIDRIPPLE_RECORD_GOLDENS=1` scratch-output path.
- [ ] Review old/new golden contact sheets and numeric diffs. Copy replacements into
      `Tests/LidRippleRendererTests/Goldens` only with the approved tuning/report hash;
      never auto-bless them during tests or tune toward old goldens.
- [ ] Generate `duo-comparison.gif` from aligned frames at a fixed 30 fps (duplicate or
      interpolate according to timestamps), reference left/candidate right, equal panel
      sizes, labels/attribution outside the active panels, no looping pause, and one
      synchronized progress/time ruler. Use ImageIO with a deterministic palette path.
- [ ] Test GIF canvas size, frame count, per-frame delay, loop metadata, labels, and
      correspondence to report frame hashes. Visually inspect the GIF in at least Safari
      and Preview to catch decoder/palette/timing differences.

## Task 6: S6 approval and milestone gates

- [ ] Run `swift test -Xswiftc -warnings-as-errors` and
      `swift build -c release -Xswiftc -warnings-as-errors`.
- [ ] Run the fidelity CLI twice from a clean checkout and assert identical report,
      contact-sheet, and GIF hashes on the recorded baseline machine; explain any
      unavoidable platform metadata rather than ignoring it.
- [ ] Confirm duration, void, and blur gates all pass and inspect their diagnostic
      overlays. Re-run M3 trace, idle-resource, and renderer-performance gates so visual
      tuning did not regress interaction or frame budget.
- [ ] Obtain explicit human approval that geometry, blur onset, void climb, rim/color,
      total duration, and overall motion are at subjective parity with the reference.
      Record approver/date and artifact/report hashes in `docs/fidelity/README.md`.
- [ ] Perform whole-milestone review, resolve Critical/Important findings, rerun every
      gate, then merge M4 to `main`, commit, and push as the milestone boundary.

## Definition of done

- [ ] Reference provenance and redistribution/derivative rights are auditable; the
      checked-in GIF and any source media comply with them.
- [ ] Alignment is fixed and reviewable, not optimized per frame to conceal differences.
- [ ] Duration, void-climb, and blur-onset/shape meet their frozen tolerances.
- [ ] The final tuning is fully represented in `FoldTuning` and preserves FR-17 plus all
      M3 lifecycle/resource behavior.
- [ ] Updated synthetic goldens pass their original <=2/255 maximum and <=0.25/255 mean
      channel-error contract and were explicitly reviewed, not automatically blessed.
- [ ] The comparison GIF is reproducible, synchronized, attributed, and committed with
      its machine-readable report and human S6 approval.
- [ ] Full tests, release build, performance regression check, and whole-milestone review
      are clean.
