import CoreGraphics
import CoreVideo
import Foundation
import Metal
import Testing
import LidRippleCapture
import LidRippleCore
import LidRippleTrace
@testable import LidRippleIntegration

/// Measurement-oriented coverage for the parts of S2-S4 that are observable
/// without a physical lid, WindowServer presentation timestamps, or TCC.
@Suite(.serialized)
@MainActor
struct FidelityPerformanceTests {
    @Test func idleSchedulesNoCaptureOrPresentationWork() async {
        let capture = PerformanceCapture()
        let output = PerformanceOutput()
        let coordinator = FoldLifecycleCoordinator(
            capture: capture,
            output: output,
            displayID: { 7 }
        )

        for index in 0..<600 {
            coordinator.ingest(.init(
                degrees: 120,
                timestamp: Double(index) / 60
            ))
        }

        let diagnostics = coordinator.diagnostics
        #expect(diagnostics.state.phase == .idle)
        #expect(diagnostics.captureActivity == .idle)
        #expect(!diagnostics.hasInstalledFrame)
        #expect(!diagnostics.overlayVisible)
        #expect(await capture.warmCount == 0)
        #expect(await capture.freezeCount == 0)
        #expect(await capture.resetCount == 0)
        #expect(output.sourceCount == 0)
        #expect(output.updateCount == 0)
    }

    @Test func canonicalTracesReportCaptureWarmBandTiming() async {
        let frameInterval = 1.0 / Double(CaptureConfiguration.warmFramesPerSecond)
        var measurements: [WarmBandMeasurement] = []

        for trace in TraceGenerator.all {
            let capture = PerformanceCapture()
            let output = PerformanceOutput()
            let coordinator = FoldLifecycleCoordinator(
                driver: FoldDriver(),
                capture: capture,
                output: output,
                displayID: { 7 }
            )
            var previous: FoldPhase = .idle
            var armedAt: TimeInterval?

            for sample in trace.angleSamples {
                let state = coordinator.ingest(sample)
                if state.phase == .armed, previous != .armed {
                    armedAt = sample.timestamp
                } else if state.phase == .folding,
                          previous != .folding,
                          let armedAt {
                    measurements.append(WarmBandMeasurement(
                        trace: trace.name,
                        seconds: sample.timestamp - armedAt
                    ))
                    break
                }
                previous = state.phase
                await coordinator.waitForPendingCapture()
            }
        }

        for measurement in measurements {
            print(String(
                format: "WARM_BAND trace=%@ duration_ms=%.2f frames_at_%dfps=%.2f",
                measurement.trace,
                measurement.seconds * 1_000,
                CaptureConfiguration.warmFramesPerSecond,
                measurement.seconds / frameInterval
            ))
        }

        let slow = measurements.first { $0.trace == "slow-close" }
        let slam = measurements.first { $0.trace == "slam" }
        #expect(slow != nil)
        #expect(slam != nil)
        #expect(slow?.seconds ?? 0 > frameInterval)

        // This is intentional instrumentation, not a claim that 10 fps is
        // sufficient: the canonical slam reaches fold start in less than one
        // capture interval, documenting why the rolling latest frame is only a
        // best effort for that motion.
        #expect(slam?.seconds ?? .infinity < frameInterval)
    }

    @Test func coordinatorSampleToOutputSchedulingBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["LIDRIPPLE_FIDELITY_BENCHMARK"] == "1" else {
            return
        }

        let frame = try makePerformanceFrame()
        let clock = ContinuousClock()
        var latencySamples: [Double] = []
        latencySamples.reserveCapacity(30)

        for _ in 0..<30 {
            let capture = PerformanceCapture(frame: frame)
            let output = PerformanceOutput()
            let coordinator = makeFastCoordinator(capture: capture, output: output)

            coordinator.ingest(.init(degrees: 120, timestamp: 0))
            coordinator.ingest(.init(degrees: 100, timestamp: 0.1))
            await coordinator.waitForPendingCapture()
            #expect(coordinator.state.phase == .armed)

            let started = clock.now
            coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
            await coordinator.waitForPendingCapture()
            latencySamples.append(seconds(started.duration(to: clock.now)))
            #expect(output.updateCount == 1)
        }

        latencySamples.sort()
        let p50 = percentile(latencySamples, 0.50)
        let p95 = percentile(latencySamples, 0.95)
        let maximum = latencySamples.last ?? 0
        print(String(
            format: "S2_SCHEDULING_PROXY samples=%d p50_ms=%.3f p95_ms=%.3f max_ms=%.3f scope=coordinator_to_output_no_hid_no_gpu_no_vsync",
            latencySamples.count,
            p50 * 1_000,
            p95 * 1_000,
            maximum * 1_000
        ))

        #expect(p95 < 0.020, "Coordinator scheduling alone exceeded the full S2 budget")
    }

    @Test func firstTenLifecycleTicksStayWithinOneSixtyHertzInterval() async throws {
        guard ProcessInfo.processInfo.environment["LIDRIPPLE_FIDELITY_BENCHMARK"] == "1" else {
            return
        }

        let capture = PerformanceCapture(frame: try makePerformanceFrame())
        let output = PerformanceOutput()
        let coordinator = makeFastCoordinator(capture: capture, output: output)
        coordinator.ingest(.init(degrees: 120, timestamp: 0))
        coordinator.ingest(.init(degrees: 100, timestamp: 0.1))
        await coordinator.waitForPendingCapture()
        coordinator.ingest(.init(degrees: 60, timestamp: 0.2))
        await coordinator.waitForPendingCapture()

        let clock = ContinuousClock()
        var samples: [Double] = []
        for index in 1...10 {
            let started = clock.now
            coordinator.tick(now: 0.2 + Double(index) / 60)
            samples.append(seconds(started.duration(to: clock.now)))
        }
        let maximum = samples.max() ?? 0
        print(String(
            format: "S3_SCHEDULING_PROXY first10_ms=%@ max_ms=%.3f scope=lifecycle_and_output_callback_no_gpu_no_vsync",
            samples.map { String(format: "%.3f", $0 * 1_000) }.joined(separator: ","),
            maximum * 1_000
        ))

        #expect(output.updateCount == 11)
        #expect(maximum < 1.0 / 60.0)
    }

    private func makeFastCoordinator(
        capture: PerformanceCapture,
        output: PerformanceOutput
    ) -> FoldLifecycleCoordinator {
        var tuning = FoldTuning.default
        tuning.filterCutoffHz = 1_000
        tuning.velocitySmoothingHz = 1_000
        tuning.deadbandDegrees = 0
        tuning.directionHoldSeconds = 0
        tuning.directionMinTravelDegrees = 0
        return FoldLifecycleCoordinator(
            driver: FoldDriver(tuning: tuning),
            capture: capture,
            output: output,
            displayID: { 7 }
        )
    }
}

private struct WarmBandMeasurement {
    let trace: String
    let seconds: TimeInterval
}

private enum PerformanceProbeError: Error {
    case noFrame
}

private actor PerformanceCapture: FoldCapturing {
    private(set) var warmCount = 0
    private(set) var freezeCount = 0
    private(set) var resetCount = 0
    private let frame: CapturedFrame?

    init(frame: CapturedFrame? = nil) {
        self.frame = frame
    }

    func warm(
        displayID: CGDirectDisplayID,
        excludingWindowID: CGWindowID
    ) async throws {
        warmCount += 1
    }

    func freeze(waitingUpTo timeout: TimeInterval) async throws -> CapturedFrame {
        freezeCount += 1
        guard let frame else { throw PerformanceProbeError.noFrame }
        return frame
    }

    func reset() async {
        resetCount += 1
    }
}

@MainActor
private final class PerformanceOutput: FoldLifecycleOutput {
    let captureExclusionWindowID: CGWindowID = 42
    private(set) var sourceCount = 0
    private(set) var updateCount = 0

    func setSource(_ frame: CapturedFrame) throws { sourceCount += 1 }
    func setFallbackSource() throws {}
    func clearSource() {}
    func update(_ state: FoldState) { updateCount += 1 }
    func hide() {}
    func setReducedQuality(_ reduced: Bool) {}
    func reconfigureForBuiltInDisplay() -> Bool { true }
}

private func makePerformanceFrame() throws -> CapturedFrame {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var cache: CVMetalTextureCache?
    let cacheStatus = CVMetalTextureCacheCreate(
        kCFAllocatorDefault,
        nil,
        device,
        nil,
        &cache
    )
    #expect(cacheStatus == kCVReturnSuccess)

    let attributes: [CFString: Any] = [
        kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        4,
        4,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )
    #expect(status == kCVReturnSuccess)
    return try CapturedFrame.make(
        pixelBuffer: try #require(pixelBuffer),
        textureCache: try #require(cache)
    )
}

private func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}

private func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = Int((Double(sorted.count - 1) * fraction).rounded(.down))
    return sorted[index]
}
