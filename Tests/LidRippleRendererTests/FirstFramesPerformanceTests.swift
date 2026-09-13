import Foundation
import Metal
import Testing
@testable import LidRippleRenderer

/// Opt-in GPU probe for S3. Unlike the steady-state benchmark, this performs
/// no test-only warm-up before frames 1...10; the production renderer itself
/// prewarms its pipeline during construction, before a visible fold.
@Suite(.serialized)
struct FirstFramesPerformanceTests {
    @Test func nativeResolutionFirstTenFramesFitSixtyHertzBudget() throws {
        guard ProcessInfo.processInfo.environment["LIDRIPPLE_FIDELITY_BENCHMARK"] == "1" else {
            return
        }

        let width = 3456
        let height = 2234
        let refreshInterval = 1.0 / 60.0
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let renderer = try FoldRenderer(device: device)
        let source = try SyntheticFrame.makeCheckerboardGradientTexture(
            device: device,
            width: width,
            height: height
        )

        let clock = ContinuousClock()
        let sourceStarted = clock.now
        try renderer.setSource(texture: source)
        let sourceSetup = performanceSeconds(sourceStarted.duration(to: clock.now))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget]
        let target = try #require(device.makeTexture(descriptor: descriptor))

        var gpuSamples: [Double] = []
        var submitToCompleteSamples: [Double] = []
        for index in 0..<10 {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            let started = clock.now
            #expect(try renderer.render(
                progress: Double(index + 1) / 10,
                to: target,
                commandBuffer: commandBuffer
            ))
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            #expect(commandBuffer.status == .completed)
            gpuSamples.append(commandBuffer.gpuEndTime - commandBuffer.gpuStartTime)
            submitToCompleteSamples.append(performanceSeconds(started.duration(to: clock.now)))
        }

        let gpuMaximum = gpuSamples.max() ?? 0
        let completionMaximum = submitToCompleteSamples.max() ?? 0
        print(String(
            format: "S3_FIRST10_GPU device=%@ resolution=%dx%d source_setup_ms=%.3f gpu_ms=%@ gpu_max_ms=%.3f submit_to_complete_ms=%@ submit_to_complete_max_ms=%.3f refresh_budget_ms=%.3f",
            device.name,
            width,
            height,
            sourceSetup * 1_000,
            gpuSamples.map { String(format: "%.3f", $0 * 1_000) }.joined(separator: ","),
            gpuMaximum * 1_000,
            submitToCompleteSamples.map { String(format: "%.3f", $0 * 1_000) }.joined(separator: ","),
            completionMaximum * 1_000,
            refreshInterval * 1_000
        ))

        #expect(gpuSamples.allSatisfy { $0 > 0 })
        #expect(
            gpuMaximum < refreshInterval,
            "A first-10 GPU frame exceeded the renderer's 60 Hz presentation interval"
        )
        #expect(
            completionMaximum < refreshInterval,
            "A first-10 submitted frame completed after the 60 Hz presentation interval"
        )
    }
}

private func performanceSeconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}
