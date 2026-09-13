import Foundation
import Testing
@testable import lidripple_fidelity

@Test func normalizedFrameSignalsHaveDefinedBlackWhiteAndEdgeBoundaries() throws {
    let black = try solid(value: 0)
    let white = try solid(value: 255)
    let edge = try PixelFrame(
        width: 3,
        height: 3,
        bytes: [
            0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255,
            0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255,
            0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255, 255,
        ]
    )

    #expect(FrameSignal.measure(black) == FrameSignal(
        darkBoundary: 1,
        darkBoundaryConfidence: 1,
        edgeEnergy: 0,
        edgeEnergyBands: [0, 0, 0],
        edgeSampleFractions: [0, 0, 0]
    ))
    #expect(FrameSignal.measure(white) == FrameSignal(
        darkBoundary: 0,
        darkBoundaryConfidence: 0,
        edgeEnergy: 0,
        edgeEnergyBands: [0, 0, 0],
        edgeSampleFractions: [0, 0, 0]
    ))
    let edgeSignal = FrameSignal.measure(edge)
    #expect(edgeSignal.darkBoundary == 0)
    #expect(edgeSignal.edgeEnergy > 0)
    #expect(edgeSignal.edgeSampleFractions == [0, 1, 0])
}

@Test func aggregateMetricsReportOnsetAndMeanCurveDifferences() throws {
    let white = try solid(value: 255)
    let black = try solid(value: 0)
    let timeline = try FidelityTimeline(frameCount: 3, duration: 1)

    let metrics = FidelityMetrics.make(
        references: [white, black, black],
        rendered: [white, white, black],
        timeline: timeline
    )

    #expect(metrics.aggregate.referenceDarkBoundaryOnsetTime == 0.5)
    #expect(metrics.aggregate.renderedDarkBoundaryOnsetTime == 1)
    #expect(metrics.aggregate.onsetTimeDifference == 0.5)
    #expect(abs(metrics.aggregate.meanDarkBoundaryDifference - 1.0 / 3.0) < 0.000_001)
    #expect(metrics.aggregate.meanEdgeEnergyDifference == 0)
    #expect(metrics.aggregate.voidPass == false)
    #expect(metrics.aggregate.blurPass == nil)
    #expect(!metrics.aggregate.objectivePass)
}

@Test func durationGateComparesRuntimeCandidateInsteadOfImposingReferenceDuration() throws {
    let textured = try PixelFrame(
        width: 2,
        height: 3,
        bytes: [
            0, 0, 0, 255, 255, 255, 255, 255,
            0, 0, 0, 255, 255, 255, 255, 255,
            0, 0, 0, 255, 255, 255, 255, 255,
        ]
    )
    let timeline = try FidelityTimeline(frameCount: 61, duration: 1, candidateDuration: 0.62)
    let metrics = FidelityMetrics.make(
        references: Array(repeating: textured, count: 61),
        rendered: Array(repeating: textured, count: 61),
        timeline: timeline,
        candidateDuration: 0.62
    )

    #expect(metrics.aggregate.referenceDuration == 1)
    #expect(metrics.aggregate.candidateDuration == 0.62)
    #expect(abs(metrics.aggregate.durationDifference - 0.38) < 0.000_001)
    #expect(!metrics.aggregate.durationPass)
    #expect(!metrics.aggregate.objectivePass)
}

private func solid(value: UInt8) throws -> PixelFrame {
    try PixelFrame(
        width: 2,
        height: 2,
        bytes: Array(repeating: [value, value, value, 255], count: 4).flatMap { $0 }
    )
}
