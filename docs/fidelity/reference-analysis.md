# iPhone Duo reference analysis

This note records a private, reproducible analysis of the opening transition in Apple's
official [iPhone Duo product film](https://www.apple.com/iphone-duo/). It is evidence for
M4 tuning, not permission to redistribute Apple's footage. The source video, decoded
frames, contact sheet, and derived GIF remain outside the repository. The exact official
[HLS master playlist](https://www.apple.com/105/media/us/iphone-duo/2026/9305e4b9-72d9-4c05-9381-b572adadd5e5/films/product/iphone-duo-product-tpl-us-2026_16x9.m3u8),
hashes, timestamps, and rights status are recorded in
[`References/Duo/reference.json`](../../References/Duo/reference.json).

## Result

The first software blur appears at frame 319 (10.643967 s), one 29.97 fps frame after
the last unaffected frame. The inner display becomes clearly visible at frame 324. Its
aperture then expands to its final observed width over 24 frame intervals (800.8 ms),
with about 91% of the width present after 16 intervals (533.9 ms). The geometry finishes
before the image: a four-frame (133.5 ms) blur-resolution tail remains after the aperture
is fully open.

Using the immutable anchor definitions from the M4 plan:

| Anchor | Absolute frame | PTS | Evidence |
|---|---:|---:|---|
| `foldStart` | 318 | 10.610600 s | Last frame without repeatable transition blur or panel separation |
| First altered frame | 319 | 10.643967 s | Right icon-band edge energy falls to 86.0% of frame 318 |
| First clear inner aperture | 324 | 10.810800 s | Sharp inner content is visibly separated from the blurred moving leaf |
| Full physical aperture | 348 | 11.611600 s | Display reaches its final measured width; left pane remains blurred |
| `foldComplete` | 352 | 11.745067 s | First of three stable frames; left-pane edge energy varies only 1.4% across frames 352–354 |

`foldStart` to `foldComplete` is 34 frame intervals, or **1.134467 seconds**. Counting
from the first actually altered frame gives 33 intervals, or 1.101100 seconds. Those are
the full transition envelope, not a claim that every lidripple geometry animation should
last that long.

## Blur timing

Blur begins locally rather than uniformly. In the fixed right icon-band ROI (source
pixels x=365–404, y=120–234), mean Sobel magnitude changes as follows:

| Frame | PTS | Edge energy | Retention vs. frame 318 |
|---:|---:|---:|---:|
| 318 | 10.610600 s | 110.7209 | 100.0% |
| 319 | 10.643967 s | 95.2606 | 86.0% |
| 320 | 10.677333 s | 61.7800 | 55.8% |
| 321 | 10.710700 s | 35.9880 | 32.5% |

This makes frame 319 the first unambiguous below-90% blur-onset crossing. The fixed
left-pane ROI reaches edge energies 42.6703, 42.9904, and 43.2708 on frames 352–354,
supporting frame 352 as the first stable completion frame. These values measure a
produced camera shot, so they establish timing only; they must not be converted directly
into a Metal blur radius.

## Fold-boundary motion

The shot has no upward-climbing black void. The closest observable signal is the moving
vertical fold seam and the sharp aperture exposed to its right. Manual annotations at
640×360 give the following axis-normalized progression. Each coordinate has an estimated
±4 px uncertainty; width is normalized to the 282 px aperture at frame 348.

| Frame | Time since first aperture | Seam x | Right edge x | Normalized visible aperture |
|---:|---:|---:|---:|---:|
| 324 | 0.0 ms | 377 | 424 | 0.167 |
| 328 | 133.5 ms | 304 | 431 | 0.450 |
| 332 | 266.9 ms | 250 | 436 | 0.660 |
| 336 | 400.4 ms | 200 | 441 | 0.855 |
| 340 | 533.9 ms | 190 | 447 | 0.911 |
| 344 | 667.3 ms | 181 | 454 | 0.968 |
| 348 | 800.8 ms | 176 | 458 | 1.000 |

For a MacBook closing comparison, rotating this fold-axis coordinate by 90° is a useful
motion analogy. It is not evidence that the film contains lidripple's literal dark void;
that styling needs a suitable closing shot or project-owned footage before claiming S6
void parity.

## Implications for tuning

The strict M4 fixed-panel alignment is not recoverable from this shot as-is.
At `foldStart`, the visible portrait outer display is partly covered by the
left hand, including its lower corners. By full aperture, the view is a
different landscape inner display with different content. Four measured
`foldStart` panel corners and a single same-content transform across the clip
therefore cannot be recorded honestly from these frames. This is separate from
Apple's unresolved redistribution rights: permission alone would not make the
current film satisfy the plan's fixed-alignment contract. A suitable
project-owned shot of one continuously visible panel, or an explicitly
approved revision of the comparison contract, is needed for S6.

- Treat geometry and blur as overlapping envelopes. Blur leads clear aperture motion by
  166.8 ms and trails full aperture by 133.5 ms.
- The current 620 ms scripted unfold is comparable to the high-energy middle of the
  reference movement, but it is shorter than both the 800.8 ms aperture phase and the
  1.1345 s complete visual envelope. It cannot by itself establish duration parity.
- Preserve the fast early motion and long ease-out: the aperture reaches roughly 85.5%
  by 400.4 ms and 91.1% by 533.9 ms, then uses another 266.9 ms for the final 8.9%.
- Do not perform a direct pixel diff against unrectified frames. The phone, hands, camera,
  screen plane, and occlusion all move during the shot. Compare normalized fold-axis
  progress and blur timing, then use visual review for geometry and color.
- Preserve the stream's declared color metadata during future decoding. It reports
  SMPTE-C primaries, an ITU-R BT.709 transfer function, an ITU-R BT.601 YCbCr matrix, and
  video-range levels rather than a simple unqualified sRGB image.

## Reproduction and temporary review artifacts

The analyzed copy is a byte-order concatenation of the HLS initialization fragment and
31 media fragments. Its SHA-256 is
`c64ee47ae78a00fff921fc4d4dbe12e56087f57d13bfa592d0c499dc94f3326b`.
Frames were requested at exact `frame × 1001 / 30000` presentation times with zero
AVFoundation tolerance.

Two local-only artifacts are available for independent visual confirmation:

- `/private/tmp/lidripple-duo-transition-contact.png` — frames 300–360 with exact PTS
- `/private/tmp/lidripple-duo-transition.gif` — frames 318–356 at 1001/30000 s per frame

Neither artifact may be copied into the repository unless redistribution and derivative
permission is separately established. The manifest therefore marks the S6 rights gate
as unresolved and the anchor selection as pending independent human confirmation.
