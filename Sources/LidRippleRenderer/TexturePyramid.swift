@preconcurrency import Metal

struct GaussianPipelines: @unchecked Sendable {
    let horizontal: any MTLComputePipelineState
    let vertical: any MTLComputePipelineState

    static func make(device: any MTLDevice, library: any MTLLibrary) throws -> GaussianPipelines {
        guard let horizontalFunction = library.makeFunction(name: "gaussianHorizontal") else {
            throw RendererError.shaderFunctionMissing("gaussianHorizontal")
        }
        guard let verticalFunction = library.makeFunction(name: "gaussianVertical") else {
            throw RendererError.shaderFunctionMissing("gaussianVertical")
        }
        return try GaussianPipelines(
            horizontal: device.makeComputePipelineState(function: horizontalFunction),
            vertical: device.makeComputePipelineState(function: verticalFunction)
        )
    }
}

/// An immutable, renderer-owned six-level Gaussian representation of one
/// captured frame. Construction completes all GPU work before publishing the
/// instance, so subsequent frames only sample it.
final class TexturePyramid: @unchecked Sendable {
    let texture: any MTLTexture
    let levelCount: Int
    let generationPassCount: Int

    static func make(
        source: any MTLTexture,
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue,
        pipelines: GaussianPipelines
    ) throws -> TexturePyramid {
        guard source.pixelFormat == .bgra8Unorm else {
            throw RendererError.unsupportedSourcePixelFormat(source.pixelFormat)
        }

        let maximumDimension = max(source.width, source.height)
        let availableLevels = Int(floor(log2(Double(maximumDimension)))) + 1
        let levelCount = min(6, availableLevels)
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = source.width
        descriptor.height = source.height
        descriptor.depth = 1
        descriptor.mipmapLevelCount = levelCount
        descriptor.arrayLength = 1
        descriptor.sampleCount = 1
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.commandBufferCreationFailed
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw RendererError.commandEncoderCreationFailed
        }
        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()

        if levelCount > 1 {
            guard let compute = commandBuffer.makeComputeCommandEncoder() else {
                throw RendererError.commandEncoderCreationFailed
            }

            for level in 1..<levelCount {
                let previousHeight = max(source.height >> (level - 1), 1)
                let levelWidth = max(source.width >> level, 1)
                let levelHeight = max(source.height >> level, 1)

                guard
                    let previous = texture.makeTextureView(
                        pixelFormat: .bgra8Unorm,
                        textureType: .type2D,
                        levels: (level - 1)..<level,
                        slices: 0..<1
                    ),
                    let destination = texture.makeTextureView(
                        pixelFormat: .bgra8Unorm,
                        textureType: .type2D,
                        levels: level..<(level + 1),
                        slices: 0..<1
                    )
                else {
                    throw RendererError.textureAllocationFailed
                }

                let intermediateDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: levelWidth,
                    height: previousHeight,
                    mipmapped: false
                )
                intermediateDescriptor.storageMode = .private
                intermediateDescriptor.usage = [.shaderRead, .shaderWrite]
                guard let intermediate = device.makeTexture(descriptor: intermediateDescriptor) else {
                    throw RendererError.textureAllocationFailed
                }

                compute.setComputePipelineState(pipelines.horizontal)
                compute.setTexture(previous, index: 0)
                compute.setTexture(intermediate, index: 1)
                dispatch(
                    encoder: compute,
                    pipeline: pipelines.horizontal,
                    width: levelWidth,
                    height: previousHeight
                )

                compute.setComputePipelineState(pipelines.vertical)
                compute.setTexture(intermediate, index: 0)
                compute.setTexture(destination, index: 1)
                dispatch(
                    encoder: compute,
                    pipeline: pipelines.vertical,
                    width: levelWidth,
                    height: levelHeight
                )

            }
            compute.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw RendererError.commandBufferFailed(
                commandBuffer.error?.localizedDescription ?? "unknown Metal command-buffer failure"
            )
        }

        return TexturePyramid(
            texture: texture,
            levelCount: levelCount,
            generationPassCount: max(levelCount - 1, 0)
        )
    }

    private init(texture: any MTLTexture, levelCount: Int, generationPassCount: Int) {
        self.texture = texture
        self.levelCount = levelCount
        self.generationPassCount = generationPassCount
    }
}

private func dispatch(
    encoder: any MTLComputeCommandEncoder,
    pipeline: any MTLComputePipelineState,
    width: Int,
    height: Int
) {
    let threadWidth = pipeline.threadExecutionWidth
    let threadHeight = max(pipeline.maxTotalThreadsPerThreadgroup / threadWidth, 1)
    encoder.dispatchThreads(
        MTLSize(width: width, height: height, depth: 1),
        threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
    )
}
