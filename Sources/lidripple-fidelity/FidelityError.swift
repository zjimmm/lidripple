import Foundation

enum FidelityError: Error, Equatable, LocalizedError {
    case helpRequested
    case missingOption(String)
    case missingValue(String)
    case unknownOption(String)
    case invalidInteger(option: String, value: String)
    case invalidNumber(option: String, value: String)
    case invalidFrameCount(Int)
    case invalidDuration(Double)
    case invalidStartTime(Double)
    case invalidDirection(String)
    case invalidCurve(String)
    case pathDoesNotExist(String)
    case noReferenceFrames(String)
    case unsupportedReference(String)
    case imageReadFailed(String)
    case imageWriteFailed(String)
    case imageDimensionsInvalid
    case bitmapContextCreationFailed
    case videoHasNoDuration(String)
    case invalidLocalHLS(String)
    case metalUnavailable
    case renderProducedNoFrame
    case outputDirectoryNotEmpty(String)
    case referenceManifestRequired
    case invalidReferenceManifest(String)
    case referenceHashMismatch(expected: String, actual: String)
    case privateReferenceAcknowledgementRequired
    case videoFrameTimeMismatch(requested: Double, actual: Double)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case .missingOption(let option):
            return "Missing required option \(option)."
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .unknownOption(let option):
            return "Unknown option \(option)."
        case .invalidInteger(let option, let value):
            return "\(option) requires an integer, not '\(value)'."
        case .invalidNumber(let option, let value):
            return "\(option) requires a number, not '\(value)'."
        case .invalidFrameCount(let count):
            return "Frame count must be at least 2, not \(count)."
        case .invalidDuration(let duration):
            return "Duration must be greater than zero, not \(duration)."
        case .invalidStartTime(let time):
            return "Start time must be zero or greater, not \(time)."
        case .invalidDirection(let direction):
            return "Direction must be 'opening' or 'closing', not '\(direction)'."
        case .invalidCurve(let curve):
            return "Curve must be 'linear' or 'smoothstep', not '\(curve)'."
        case .pathDoesNotExist(let path):
            return "Path does not exist: \(path)"
        case .noReferenceFrames(let path):
            return "No PNG reference frames found at \(path)."
        case .unsupportedReference(let path):
            return "Reference must be a PNG directory or MOV/MP4/M4V video: \(path)"
        case .imageReadFailed(let path):
            return "Could not read image: \(path)"
        case .imageWriteFailed(let path):
            return "Could not write image: \(path)"
        case .imageDimensionsInvalid:
            return "Image dimensions must be positive."
        case .bitmapContextCreationFailed:
            return "Could not create a bitmap context."
        case .videoHasNoDuration(let path):
            return "Reference video has no usable duration: \(path)"
        case .invalidLocalHLS(let path):
            return "Local HLS playlist is missing an init map or media segments: \(path)"
        case .metalUnavailable:
            return "Metal is unavailable on this Mac."
        case .renderProducedNoFrame:
            return "The renderer did not produce a frame after its source was installed."
        case .outputDirectoryNotEmpty(let path):
            return "Output directory must be absent or empty to avoid overwriting files: \(path)"
        case .referenceManifestRequired:
            return "Video references require --reference-manifest with provenance, rights, hash, and anchor metadata."
        case .invalidReferenceManifest(let reason):
            return "Invalid reference manifest: \(reason)"
        case .referenceHashMismatch(let expected, let actual):
            return "Reference hash mismatch: expected \(expected), got \(actual)."
        case .privateReferenceAcknowledgementRequired:
            return "Reference redistribution rights are not established; pass --private-reference for local-only analysis."
        case .videoFrameTimeMismatch(let requested, let actual):
            return "Video decoder returned PTS \(actual) for exact request \(requested)."
        }
    }
}
