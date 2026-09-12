import CoreGraphics
import CoreVideo

public enum CaptureError: Error, Equatable, Sendable {
    case metalUnavailable
    case displayNotFound(CGDirectDisplayID)
    case excludedWindowNotFound(CGWindowID)
    case conflictingWarmup
    case notWarming
    case noFrameAvailable
    case unsupportedPixelFormat(OSType)
    case textureCacheCreationFailed(CVReturn)
    case textureCreationFailed(CVReturn)
    case streamStopped(String)
}
