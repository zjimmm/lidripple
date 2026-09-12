import Metal

public enum RendererError: Error, Equatable {
    case shaderFunctionMissing(String)
    case unsupportedSourcePixelFormat(MTLPixelFormat)
    case textureAllocationFailed
    case commandQueueCreationFailed
    case commandBufferCreationFailed
    case commandEncoderCreationFailed
    case commandBufferFailed(String)
}
