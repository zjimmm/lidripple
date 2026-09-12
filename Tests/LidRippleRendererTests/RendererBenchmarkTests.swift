import Foundation
import Metal
import Testing
@testable import LidRippleRenderer

@Test func nativeResolutionRenderBenchmark() throws {
    guard ProcessInfo.processInfo.environment["LIDRIPPLE_RENDER_BENCHMARK"] == "1" else {
        return
    }

    let width = 3456
    let height = 2234
    let device = try #require(MTLCreateSystemDefaultDevice())
    let commandQueue = try #require(device.makeCommandQueue())
    let renderer = try FoldRenderer(device: device)
    let source = try SyntheticFrame.makeCheckerboardGradientTexture(
        device: device,
        width: width,
        height: height
    )
    try renderer.setSource(texture: source)

    let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    targetDescriptor.storageMode = .private
    targetDescriptor.usage = [.renderTarget]
    let target = try #require(device.makeTexture(descriptor: targetDescriptor))

    func measure(progress: Double) throws -> Double {
        let commandBuffer = try #require(commandQueue.makeCommandBuffer())
        #expect(try renderer.render(progress: progress, to: target, commandBuffer: commandBuffer))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed)
        return commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
    }

    for index in 0..<8 {
        _ = try measure(progress: Double(index) / 8)
    }

    var samples: [Double] = []
    for index in 0..<40 {
        samples.append(try measure(progress: Double(index % 20) / 20))
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
    let isM1ProBaseline = device.name.localizedCaseInsensitiveContains("M1 Pro")
    print(String(
        format: "RENDER_BENCHMARK device=%@ resolution=%dx%d median_ms=%.3f p95_ms=%.3f baseline=%@",
        device.name,
        width,
        height,
        median * 1_000,
        p95 * 1_000,
        isM1ProBaseline ? "M1 Pro" : "informational"
    ))

    #expect(median > 0)
    if isM1ProBaseline {
        #expect(p95 < 0.004, "M1 Pro p95 render time was \(p95 * 1_000) ms")
    }
}
