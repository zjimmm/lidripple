import Testing
import Foundation
@testable import LidRippleCore
@testable import LidRippleTrace

/// Replays a trace through a driver synchronously and returns every state.
/// Synchronous and deterministic by design: spec section 12 requires fixed
/// timesteps, not wall-clock timing.
private func run(_ trace: Trace, tuning: FoldTuning = .default) -> [FoldState] {
    let driver = FoldDriver(tuning: tuning)
    return trace.angleSamples.map { driver.ingest($0) }
}

@Test func slowCloseReachesFullFoldAndSeals() {
    let states = run(TraceGenerator.slowClose())
    #expect(states.map(\.progress).max()! > 0.99)
    #expect(states.last!.phase == .sealed)
}

@Test func slowCloseIsGraduallyProgressiveRatherThanASnap() {
    let states = run(TraceGenerator.slowClose())
    // The viscous case should spend real time in the visible middle of the fold.
    let midRange = states.filter { $0.progress > 0.2 && $0.progress < 0.8 }
    #expect(midRange.count > 30)      // more than half a second at 60 Hz
}

@Test func slamStaysWithinTheProgressClamp() {
    let states = run(TraceGenerator.slam())
    #expect(states.map(\.progress).max()! <= FoldTuning.default.maxProgress + 1e-9)
    #expect(states.last!.phase == .sealed)
}

@Test func hesitantCloseNeverGoesBackwardsDuringItsPauses() {
    let states = run(TraceGenerator.hesitantClose())
    // Pauses must hold progress, not bleed it away or trigger an unfold.
    #expect(!states.contains { $0.phase == .unfolding })
    #expect(states.last!.phase == .sealed)
}

@Test func stopAndReopenReturnsToIdleWithoutEverCompletingTheFold() {
    let states = run(TraceGenerator.stopAndReopen())
    #expect(states.map(\.progress).max()! < 1.0)
    #expect(states.last!.phase == .idle)
    #expect(states.last!.progress == 0)
}

@Test func wiggleAtRestProducesNoAnimationWhatsoever() {
    let states = run(TraceGenerator.wiggleAtRest())
    #expect(states.allSatisfy { $0.phase == .idle })
    #expect(states.allSatisfy { $0.progress == 0 })
}

@Test func closeReopenCloseEndsSealedWithNoOrphanedState() {
    let states = run(TraceGenerator.closeReopenClose())
    #expect(states.last!.phase == .sealed)
    // It must genuinely pass through idle in the middle, not just unfold partway.
    #expect(states.contains { $0.phase == .idle && $0.progress == 0 })
    #expect(states.contains { $0.phase == .unfolding })
}

@Test func everyCanonicalTraceEndsInATerminalPhase() {
    for trace in TraceGenerator.all {
        let last = run(trace).last!
        #expect(
            [.idle, .sealed].contains(last.phase),
            "\(trace.name) ended mid-transition in \(last.phase)"
        )
    }
}

@Test func progressIsAlwaysInRangeForEveryTrace() {
    for trace in TraceGenerator.all {
        for state in run(trace) {
            #expect(state.progress >= 0, "\(trace.name) went negative")
            #expect(state.progress <= FoldTuning.default.maxProgress + 1e-9, "\(trace.name) overshot")
        }
    }
}

@Test func loweringIntensityDoesNotChangeTimingOrPhases() {
    // Spec FR-17: intensity is a render-only control.
    let full = run(TraceGenerator.slowClose(), tuning: .default)
    let soft = run(TraceGenerator.slowClose(), tuning: FoldTuning.default.withIntensity(0.5))
    #expect(full.map(\.phase) == soft.map(\.phase))
    #expect(zip(full, soft).allSatisfy { abs($0.progress - $1.progress) < 1e-9 })
}
