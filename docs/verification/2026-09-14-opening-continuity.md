# Opening continuity correction

Owner reported a static, pre-drawn appearance after the wake-only depth cap and
entrance ramp. Those changes are removed; presentation now forwards driver progress
unchanged for both effects.

Reference inspected: https://www.apple.com/ph/iphone-duo/ — interactive product
viewer at closed, partially folded, and open poses. The relevant visual property
is continuous shape/content attachment to pose, not an independent entrance
animation. This is a qualitative inspection, not a frame-matched fidelity claim.
No reference assets were copied into the app.

Real app wake logs on the owner's M4 (2026-09-14, 14:48 local) show approximately
203–240 ms from fresh-capture start to installed frame; first displayed angles
include 11°, 15°, 23°, and 49°. These are startup measurements, not frame-rate or
physical end-to-end latency measurements.

## Accepted frosted handoff

The final prototype adds a native frosted cover in the capture-excluded overlay
after session authorization, before capture startup awaits. It clears over 160 ms
once the measured opening frame is available, without changing that frame's
geometry. A 550 ms timeout and immediate lock/abort cleanup bound its lifetime.
The owner reported: “nice i think its much smoother” and requested committing and
pushing this state. All 309 tests passed, including timeout and lock cancellation.
This is qualitative owner acceptance, not proof of eliminating every system frame
visible before the unlock notification.

The driver also released sensor-paced opening after a timeout measured from
animation start, regardless of fresh input. It now measures that timeout from the
latest valid sensor reading. A paused or slowly opening lid with fresh readings
retains its measured pose; actual input loss still releases safely.

Regression coverage includes a three-second pause followed by a three-second
whole-degree opening, monotonic progress, numerous distinct rendered frames for
both effects, unmodified presentation progress, and stale-input release.

Unchanged limitations: fresh capture is still required after unlock; no old desktop
texture or login-window overlay is reused. Late-start suppression remains. macOS
may expose the desktop before the app receives its unlock event. Physical smoothness
and the initial wake handoff still require the owner's real-lid check.
