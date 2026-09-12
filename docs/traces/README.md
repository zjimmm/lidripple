# Lid traces

A trace is a recorded sequence of real lid angles. Traces are how the fold
animation gets tested without closing a laptop hundreds of times (spec §12).

## Recording one

```bash
swift run lidripple-trace record --name slow-close --out docs/traces/slow-close.json
```

Move the lid, then Ctrl-C to save.

## Inspecting one

```bash
swift run lidripple-trace info docs/traces/slow-close.json
swift run lidripple-trace replay docs/traces/slow-close.json
```

`replay` prints the phase and progress `FoldDriver` produces for each sample —
the fastest way to see why a motion behaves the way it does.

## Synthetic vs recorded

`TraceGenerator` builds the six canonical motions deterministically, so the test
suite runs identically on any machine, including one with no lid sensor. Real
recordings are committed here as extra fixtures during M4, when the animation is
tuned against genuine hand motion.
