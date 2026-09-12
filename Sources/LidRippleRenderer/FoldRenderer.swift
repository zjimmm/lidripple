import Foundation
@preconcurrency import Metal
import LidRippleCapture
import LidRippleCore

/// Converts one frozen captured frame and one progress value into a Metal target.
/// Pipeline, mesh, and sampler state are immutable; per-frame work is limited to
/// one uniform write and one indexed draw.
public final class FoldRenderer {
    public let device: any MTLDevice
    public let tuning: FoldTuning

    private let commandQueue: any MTLCommandQueue
    private let renderPipeline: any MTLRenderPipelineState
    private let gaussianPipelines: GaussianPipelines
    private let vertexBuffer: any MTLBuffer
    private let indexBuffer: any MTLBuffer
    private let indexCount: Int
    private let sampler: any MTLSamplerState
    private let uniformBuffers: [any MTLBuffer]
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    private let stateLock = NSLock()
    private var nextUniformBuffer = 0
    private var pyramid: TexturePyramid?
    private(set) var pyramidBuildCount = 0

    public convenience init(tuning: FoldTuning = .default) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalUnavailable
        }
        try self.init(device: device, tuning: tuning)
    }

    public init(device: any MTLDevice, tuning: FoldTuning = .default) throws {
        self.device = device
        self.tuning = tuning

        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        let library = try FoldShaderLibrary.make(device: device)
        gaussianPipelines = try GaussianPipelines.make(device: device, library: library)

        guard let vertexFunction = library.makeFunction(name: "foldVertex") else {
            throw RendererError.shaderFunctionMissing("foldVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "foldFragment") else {
            throw RendererError.shaderFunctionMissing("foldFragment")
        }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<FoldMesh.Vertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.label = "lidripple fold"
        renderDescriptor.vertexFunction = vertexFunction
        renderDescriptor.fragmentFunction = fragmentFunction
        renderDescriptor.vertexDescriptor = vertexDescriptor
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)

        let mesh = try FoldMesh.make()
        let madeVertexBuffer: (any MTLBuffer)? = mesh.vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        }
        let madeIndexBuffer: (any MTLBuffer)? = mesh.indices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        }
        guard let vertexBuffer = madeVertexBuffer, let indexBuffer = madeIndexBuffer else {
            throw RendererError.bufferAllocationFailed
        }
        vertexBuffer.label = "lidripple fold vertices"
        indexBuffer.label = "lidripple fold indices"
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        indexCount = mesh.indices.count

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.bufferAllocationFailed
        }
        self.sampler = sampler

        var uniformBuffers: [any MTLBuffer] = []
        uniformBuffers.reserveCapacity(3)
        for index in 0..<3 {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<FoldUniforms>.stride,
                options: .storageModeShared
            ) else {
                throw RendererError.bufferAllocationFailed
            }
            buffer.label = "lidripple uniforms \(index)"
            uniformBuffers.append(buffer)
        }
        self.uniformBuffers = uniformBuffers
    }

    public func setSource(_ frame: CapturedFrame) throws {
        try setSource(texture: frame.texture)
    }

    func setSource(texture: any MTLTexture) throws {
        guard texture.device.registryID == device.registryID else {
            throw RendererError.sourceDeviceMismatch
        }
        let replacement = try TexturePyramid.make(
            source: texture,
            device: device,
            commandQueue: commandQueue,
            pipelines: gaussianPipelines
        )

        stateLock.lock()
        pyramid = replacement
        pyramidBuildCount += 1
        stateLock.unlock()
    }

    public func clearSource() {
        stateLock.lock()
        pyramid = nil
        stateLock.unlock()
    }

    /// Encodes one frame into `target`. The caller owns command-buffer commit and
    /// presentation. Returns false without encoding when no source is installed.
    @discardableResult
    public func render(
        progress: Double,
        to target: any MTLTexture,
        commandBuffer: any MTLCommandBuffer
    ) throws -> Bool {
        guard target.pixelFormat == .bgra8Unorm else {
            throw RendererError.unsupportedTargetPixelFormat(target.pixelFormat)
        }
        guard target.device.registryID == device.registryID else {
            throw RendererError.sourceDeviceMismatch
        }

        stateLock.lock()
        guard let pyramid else {
            stateLock.unlock()
            return false
        }
        stateLock.unlock()

        inFlightSemaphore.wait()
        var completionOwnsSemaphore = false
        defer {
            if !completionOwnsSemaphore { inFlightSemaphore.signal() }
        }

        stateLock.lock()
        let uniformBuffer = uniformBuffers[nextUniformBuffer]
        nextUniformBuffer = (nextUniformBuffer + 1) % uniformBuffers.count
        stateLock.unlock()

        var uniforms = FoldUniforms.make(
            progress: progress,
            tuning: tuning,
            viewportSize: SIMD2<Int>(target.width, target.height),
            sourceSize: SIMD2<Int>(pyramid.texture.width, pyramid.texture.height)
        )
        withUnsafeBytes(of: &uniforms) { bytes in
            uniformBuffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: tuning.warmBlackRed,
            green: tuning.warmBlackGreen,
            blue: tuning.warmBlackBlue,
            alpha: 1
        )
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw RendererError.commandEncoderCreationFailed
        }
        encoder.label = "lidripple fold frame"
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(pyramid.texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        encoder.endEncoding()

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        completionOwnsSemaphore = true
        return true
    }
}
