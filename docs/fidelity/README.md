# Fidelity evidence

M4 adds a deterministic comparison harness and measures the real transition in Apple's
official iPhone Duo product film. The source is used as a private tuning reference only:
Apple has not granted this project redistribution or derivative-media permission, so the
source frames and generated side-by-side GIF are deliberately absent from git.

The checked-in evidence is:

- [`../../References/Duo/reference.json`](../../References/Duo/reference.json): exact
  source URL, hashes, color metadata, 29.97 fps frame anchors, and rights status;
- [`reference-analysis.md`](reference-analysis.md): blur onset, aperture progression,
  duration, and limitations;
- [`report.json`](report.json): candidate settings, local artifact hashes, visual review,
  performance measurements, and the remaining S6 publication gate;
- [`tuning.json`](tuning.json): the accepted sparse override file. It is intentionally
  empty because review did not justify changing the renderer defaults.

## Reproduce locally

Download the official 640×360 AVC HLS variant and its initialization/media fragments
into a local directory, preserving the playlist's relative paths. The current Apple shot
cannot satisfy strict alignment as-is: hands hide the `foldStart` panel's lower corners,
and the shot changes from outer portrait content to a different inner landscape panel.
Do not invent missing corners. With a suitable lawfully usable reference, replace the
manifest's `alignment: null` with measured fixed display corners, corrected output
dimensions, and normalized exclusion polygons for hands/glare. The tool deliberately
fails until this evidence exists. Then run:

```sh
swift run lidripple-fidelity \
  --reference /path/to/prog_index.m3u8 \
  --reference-manifest References/Duo/reference.json \
  --private-reference \
  --output-dir /tmp/lidripple-m4-review \
  --frames 35 \
  --start-time 10.6106 \
  --duration 1.1344666666666667 \
  --direction opening \
  --curve smoothstep \
  --tuning docs/fidelity/tuning.json
```

The command emits normalized reference and rendered PNG sequences, mask/boundary/band
diagnostic overlays, labeled comparison
PNGs, `comparison.gif`, `contact-sheet.png`, `metrics.json`, and `manifest.json`. The
manifest hashes every input, including all local HLS fragments. The metrics are diagnostic
curves; they do not convert a produced camera shot into a false pixel-perfect score.
The private-reference flag is an explicit acknowledgement that generated media must remain
local. Video runs fail on a missing manifest, source-hash mismatch, or anchor mismatch.
Output directories must be new or empty; the tool never deletes existing caller files.

Candidate progress uses `FoldTuning.scriptedUnfoldSeconds` (currently 620 ms) on the
reference timestamps. It is not stretched to the 1.134467-second film envelope. Consequently
the duration gate currently fails by 514.467 ms, which is useful evidence rather than a
comparison configured to pass itself.
The checked-in `report.json` predates the 2026-09-13 retained-content renderer
revision (delayed geometry, local hinge shadow, non-duplicating contextual backing, late seal fade).
Its candidate metrics and tuning hash are historical, not approval of the revised
renderer; regenerate and review them before claiming S6.
The corrected `foldStart` panel frame is the renderer source; the CLI does not accept a
separate image that could make the two sides incomparable.

## Publication gate

Owner decision, 2026-09-15: defer S6 for v1 and use the owner's current visual
approval as product acceptance. This does not mark the comparison complete or grant
rights to publish reference media. No pixel-identical claims are made.

S6 is not marked complete until a lawful reference can appear in the repository. Once
permission or project-owned real-device footage exists, rerun the exact command, verify
the generated hashes, visually approve the GIF, and place it at
`docs/fidelity/duo-comparison.gif`. Do not copy the current private Apple-derived artifact
into the repository merely to make the checklist green.
