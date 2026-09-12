import Metal

public enum RendererError: Error, Equatable {
    case metalUnavailable
    case shaderFunctionMissing(String)
    case unsupportedSourcePixelFormat(MTLPixelFormat)
    case unsupportedTargetPixelFormat(MTLPixelFormat)
    case sourceDeviceMismatch
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandQueueCreationFailed
    case commandBufferCreationFailed
    case commandEncoderCreationFailed
    case commandBufferFailed(String)
}
