import Testing
@testable import lidripple_fidelity

@Test func timelineIncludesExactEndpointsAndUniformIntervals() throws {
    let timeline = try FidelityTimeline(frameCount: 3, duration: 0.62)

    #expect(timeline.samples == [
        .init(index: 0, progress: 0, time: 0),
        .init(index: 1, progress: 0.5, time: 0.31),
        .init(index: 2, progress: 1, time: 0.62),
    ])
}

@Test func openingTimelineMapsProgressFromSealedToOpen() throws {
    let timeline = try FidelityTimeline(frameCount: 3, duration: 0.62, direction: .opening)

    #expect(timeline.direction == .opening)
    #expect(timeline.samples.map(\.progress) == [1, 0.5, 0])
    #expect(timeline.samples.map(\.time) == [0, 0.31, 0.62])
}

@Test func smoothstepCurveMatchesTheScriptedUnfoldShape() throws {
    let timeline = try FidelityTimeline(
        frameCount: 5,
        duration: 1,
        direction: .opening,
        curve: .smoothstep
    )

    #expect(timeline.curve == .smoothstep)
    #expect(timeline.samples.map(\.progress) == [1, 0.84375, 0.5, 0.15625, 0])
}

@Test func candidateDurationDoesNotGetStretchedToReferenceDuration() throws {
    let timeline = try FidelityTimeline(
        frameCount: 5,
        duration: 1,
        candidateDuration: 0.5,
        direction: .opening,
        curve: .linear
    )

    #expect(timeline.candidateDuration == 0.5)
    #expect(timeline.samples.map(\.progress) == [1, 0.5, 0, 0, 0])
    #expect(timeline.samples.map(\.time) == [0, 0.25, 0.5, 0.75, 1])
}

@Test func timelineRejectsDegenerateInputs() {
    #expect(throws: FidelityError.invalidFrameCount(1)) {
        try FidelityTimeline(frameCount: 1, duration: 0.62)
    }
    #expect(throws: FidelityError.invalidDuration(0)) {
        try FidelityTimeline(frameCount: 2, duration: 0)
    }
}
