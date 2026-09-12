import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Metal
@preconcurrency import ScreenCaptureKit

protocol CaptureSession: Sendable {
    func start() async throws
    func stop() async
    func latestFrame() async throws -> CapturedFrame?
}

typealias CaptureSessionFactory = @Sendable (
    _ displayID: CGDirectDisplayID,
    _ excludedWindowID: CGWindowID
) async throws -> any CaptureSession

/// The permission-bearing ScreenCaptureKit implementation behind the coordinator's
/// test seam. Every instance owns at most one stream and one serial callback queue.
final class ScreenCaptureSession: NSObject, CaptureSession, SCStreamDelegate, @unchecked Sendable {
    private let displayID: CGDirectDisplayID
    private let excludedWindowID: CGWindowID
    private let device: any MTLDevice
    private let outputQueue = DispatchQueue(
        label: "com.lidripple.capture.frames",
        qos: .userInteractive
    )
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var receiver: FrameReceiver?
    private var terminalError: CaptureError?

    init(
        displayID: CGDirectDisplayID,
        excludedWindowID: CGWindowID,
        device: any MTLDevice
    ) {
        self.displayID = displayID
        self.excludedWindowID = excludedWindowID
        self.device = device
    }

    func start() async throws {
        let alreadyStarted = stateLock.withLock { self.stream != nil }
        guard !alreadyStarted else { return }

        let content = try await SCShareableContent.current
        let display = try Self.requireDisplay(displayID, in: content.displays)
        let excludedWindow = try Self.requireWindow(excludedWindowID, in: content.windows)

        let filter = SCContentFilter(display: display, excludingWindows: [excludedWindow])
        let configuration = CaptureConfiguration.make(
            contentRect: filter.contentRect,
            pointPixelScale: filter.pointPixelScale
        )
        let cache = try CapturedFrame.makeTextureCache(device: device)
        let receiver = FrameReceiver(textureCache: cache)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(
            receiver,
            type: .screen,
            sampleHandlerQueue: outputQueue
        )

        do {
            try await stream.startCapture()
        } catch {
            try? stream.removeStreamOutput(receiver, type: .screen)
            throw error
        }

        stateLock.withLock {
            self.receiver = receiver
            self.stream = stream
            terminalError = nil
        }
    }

    private static func requireDisplay(
        _ displayID: CGDirectDisplayID,
        in displays: [SCDisplay]
    ) throws -> SCDisplay {
        for display in displays where display.displayID == displayID {
            return display
        }
        throw CaptureError.displayNotFound(displayID)
    }

    private static func requireWindow(
        _ windowID: CGWindowID,
        in windows: [SCWindow]
    ) throws -> SCWindow {
        for window in windows where window.windowID == windowID {
            return window
        }
        throw CaptureError.excludedWindowNotFound(windowID)
    }

    func stop() async {
        let (stream, receiver) = stateLock.withLock {
            let owned = (self.stream, self.receiver)
            self.stream = nil
            self.receiver = nil
            return owned
        }

        guard let stream else { return }
        try? await stream.stopCapture()
        if let receiver {
            try? stream.removeStreamOutput(receiver, type: .screen)
        }
    }

    func latestFrame() async throws -> CapturedFrame? {
        let (error, receiver) = stateLock.withLock { (terminalError, self.receiver) }
        if let error { throw error }
        return receiver?.latestFrame()
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        stateLock.lock()
        terminalError = .streamStopped(error.localizedDescription)
        stateLock.unlock()
    }
}

final class FrameReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let textureCache: CVMetalTextureCache
    private let frameLock = NSLock()
    private var frame: CapturedFrame?

    init(textureCache: CVMetalTextureCache) {
        self.textureCache = textureCache
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard
            outputType == .screen,
            SampleBufferFrameStatus.isComplete(sampleBuffer),
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let captured = try? CapturedFrame.make(
                pixelBuffer: pixelBuffer,
                textureCache: textureCache
            )
        else { return }

        frameLock.lock()
        frame = captured
        frameLock.unlock()
    }

    func latestFrame() -> CapturedFrame? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return frame
    }
}

enum SampleBufferFrameStatus {
    static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            sampleBuffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let first = attachments.first
        else { return false }
        return isComplete(first)
    }

    static func isComplete(_ attachments: [SCStreamFrameInfo: Any]) -> Bool {
        let value = attachments[.status]
        let rawValue: Int?
        if let number = value as? NSNumber {
            rawValue = number.intValue
        } else {
            rawValue = value as? Int
        }
        guard let rawValue else { return false }
        return SCFrameStatus(rawValue: rawValue) == .complete
    }
}
