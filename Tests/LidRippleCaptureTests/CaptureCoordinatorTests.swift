import CoreGraphics
import CoreVideo
import Metal
import Testing
@testable import LidRippleCapture

@Test func coordinatorStartsIdleAndRejectsFreeze() async throws {
    let session = FakeCaptureSession()
    let coordinator = CaptureCoordinator { _, _ in session }

    #expect(await coordinator.state == .idle)
    await #expect(throws: CaptureError.notWarming) {
        try await coordinator.freeze()
    }
}

@Test func coordinatorWarmsFreezesAndResetsIdempotently() async throws {
    let frame = try makeCoordinatorTestFrame()
    let session = FakeCaptureSession(frame: frame)
    let coordinator = CaptureCoordinator { _, _ in session }

    try await coordinator.warm(displayID: 1, excludingWindowID: 2)
    try await coordinator.warm(displayID: 1, excludingWindowID: 2)
    #expect(await coordinator.state == .warming)
    #expect(await session.startCount == 1)

    await #expect(throws: CaptureError.conflictingWarmup) {
        try await coordinator.warm(displayID: 3, excludingWindowID: 2)
    }

    let frozen = try await coordinator.freeze()
    #expect(frozen === frame)
    #expect(await coordinator.frozenFrame === frame)
    #expect(await coordinator.state == .frozen)
    #expect(await session.stopCount == 1)

    await coordinator.reset()
    await coordinator.reset()
    #expect(await coordinator.state == .idle)
    #expect(await coordinator.frozenFrame == nil)
    #expect(await session.stopCount == 1)

    try await coordinator.warm(displayID: 1, excludingWindowID: 2)
    #expect(await session.startCount == 2)
    await coordinator.reset()
    #expect(await session.stopCount == 2)
}

@Test func coordinatorStopsAndReturnsIdleWhenNoFrameArrives() async throws {
    let session = FakeCaptureSession()
    let coordinator = CaptureCoordinator { _, _ in session }

    try await coordinator.warm(displayID: 1, excludingWindowID: 2)
    await #expect(throws: CaptureError.noFrameAvailable) {
        try await coordinator.freeze()
    }
    #expect(await coordinator.state == .idle)
    #expect(await session.stopCount == 1)
}

@Test func coordinatorRecoversFromStartFailure() async throws {
    let session = FakeCaptureSession(startError: .streamStopped("test"))
    let coordinator = CaptureCoordinator { _, _ in session }

    await #expect(throws: CaptureError.streamStopped("test")) {
        try await coordinator.warm(displayID: 1, excludingWindowID: 2)
    }
    #expect(await coordinator.state == .idle)
    #expect(await session.stopCount == 1)
}

@Test func resetInvalidatesAStartThatFinishesLater() async throws {
    let gate = StartGate()
    let session = FakeCaptureSession(startGate: gate)
    let coordinator = CaptureCoordinator { _, _ in session }

    let warmTask = Task {
        try await coordinator.warm(displayID: 1, excludingWindowID: 2)
    }
    await gate.waitUntilEntered()
    await coordinator.reset()
    await gate.open()

    await #expect(throws: CancellationError.self) {
        try await warmTask.value
    }
    #expect(await coordinator.state == .idle)
    #expect(await session.stopCount >= 1)
}

private actor FakeCaptureSession: CaptureSession {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let frame: CapturedFrame?
    private let startError: CaptureError?
    private let startGate: StartGate?

    init(
        frame: CapturedFrame? = nil,
        startError: CaptureError? = nil,
        startGate: StartGate? = nil
    ) {
        self.frame = frame
        self.startError = startError
        self.startGate = startGate
    }

    func start() async throws {
        startCount += 1
        if let startGate {
            await startGate.enterAndWait()
        }
        if let startError { throw startError }
    }

    func stop() async {
        stopCount += 1
    }

    func latestFrame() async throws -> CapturedFrame? {
        frame
    }
}

private actor StartGate {
    private var entered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters { waiter.resume() }

        guard !isOpen else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private func makeCoordinatorTestFrame() throws -> CapturedFrame {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let cache = try CapturedFrame.makeTextureCache(device: device)
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
        textureCache: cache
    )
}
