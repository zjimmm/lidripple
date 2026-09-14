import Foundation
import Testing
@testable import LidRippleAppSupport

@Suite(.serialized)
@MainActor
struct DebugScrubberControllerTests {
    @Test func playbackEasesIntoMotionAndReversalPreservesPosition() async {
        let session = FakeDebugSession()
        let scheduler = FakeDebugScheduler()
        let clock = ClockBox()
        let controller = DebugScrubberController(session: session, scheduler: scheduler,
            now: { clock.value }, maximumProgress: 1, playbackDuration: 1, presentsPanel: false)
        await controller.open(intensity: 1)
        controller.playForward()
        clock.value = 1.0 / 60
        scheduler.fire()
        #expect(controller.progress > 0)
        #expect(controller.progress < 1.0 / 60)
        for _ in 0..<20 {
            clock.value += 1.0 / 60
            scheduler.fire()
        }
        let before = controller.progress
        controller.playReverse()
        #expect(controller.progress == before)
        controller.tick(now: .nan)
        controller.setProgress(.nan)
        #expect(controller.progress == before)
        clock.value += 1.0 / 60
        scheduler.fire()
        #expect(controller.progress < before)
        #expect(scheduler.activeCount == 1)
    }
    @Test func openInstallsSyntheticSessionAndRepeatedOpenIsIdempotent() async {
        let session = FakeDebugSession()
        let scheduler = FakeDebugScheduler()
        let controller = DebugScrubberController(
            session: session,
            scheduler: scheduler,
            presentsPanel: false
        )

        await controller.open(intensity: 0.2)
        await controller.open(intensity: 1)
        #expect(controller.isOpen)
        #expect(session.preparedIntensities == [0.5])
        #expect(session.updates.first == DebugUpdate(progress: 0, direction: 1))
        #expect(scheduler.scheduleCount == 0)
    }

    @Test func sliderEndpointsAndIntensityClampReachSameSession() async {
        let session = FakeDebugSession()
        let controller = DebugScrubberController(
            session: session,
            scheduler: FakeDebugScheduler(),
            maximumProgress: 1.06,
            presentsPanel: false
        )
        await controller.open(intensity: 1)
        controller.setProgress(8)
        #expect(controller.progress == 1.06)
        #expect(session.updates.last == DebugUpdate(progress: 1.06, direction: 1))
        controller.setProgress(-8)
        #expect(controller.progress == 0)
        #expect(session.updates.last == DebugUpdate(progress: 0, direction: -1))
        controller.setIntensity(0.1)
        controller.setIntensity(9)
        #expect(session.intensities == [0.5, 1])
    }

    @Test func forwardAndReverseUseAtMostOneTimerAndStopAtEndpoints() async {
        let session = FakeDebugSession()
        let scheduler = FakeDebugScheduler()
        let clock = ClockBox()
        let controller = DebugScrubberController(
            session: session,
            scheduler: scheduler,
            now: { clock.value },
            maximumProgress: 1,
            playbackDuration: 1,
            presentsPanel: false
        )
        await controller.open(intensity: 1)

        controller.playForward()
        #expect(controller.isPlaying)
        #expect(scheduler.activeCount == 1)
        controller.playReverse()
        #expect(scheduler.activeCount == 1)
        #expect(scheduler.cancelCount == 1)

        controller.setProgress(1)
        controller.playReverse()
        for _ in 0..<20 {
            clock.value += 1.0 / 15.0
            scheduler.fire()
        }
        #expect(controller.progress == 0)
        #expect(!controller.isPlaying)
        #expect(scheduler.activeCount == 0)
    }

    @Test func closeWhilePlayingStopsWorkAndRestoresExactlyOnce() async {
        let session = FakeDebugSession()
        let scheduler = FakeDebugScheduler()
        let controller = DebugScrubberController(
            session: session,
            scheduler: scheduler,
            presentsPanel: false
        )
        await controller.open(intensity: 1)
        controller.playForward()
        await controller.close()
        await controller.close()
        #expect(!controller.isOpen)
        #expect(!controller.isPlaying)
        #expect(scheduler.activeCount == 0)
        #expect(session.finishCount == 1)
    }

    @Test func systemRestrictionSynchronouslyCancelsPlaybackAndHidesSession() async {
        let session = FakeDebugSession()
        let scheduler = FakeDebugScheduler()
        let controller = DebugScrubberController(
            session: session,
            scheduler: scheduler,
            presentsPanel: false
        )
        await controller.open(intensity: 1)
        controller.playForward()

        controller.abortForSystemRestriction()

        #expect(!controller.isOpen)
        #expect(!controller.isPlaying)
        #expect(scheduler.activeCount == 0)
        scheduler.fire()
        #expect(session.updates.count == 1)
    }

    @Test func preparationFailureLeavesNoWindowOrTimer() async {
        let session = FakeDebugSession()
        session.prepareError = TestDebugError.expected
        let scheduler = FakeDebugScheduler()
        var errors: [String] = []
        let controller = DebugScrubberController(
            session: session,
            scheduler: scheduler,
            presentsPanel: false,
            reportError: { errors.append($0) }
        )
        await controller.open(intensity: 1)
        #expect(!controller.isOpen)
        #expect(!controller.isPlaying)
        #expect(scheduler.scheduleCount == 0)
        #expect(errors.count == 1)
    }
}

private struct DebugUpdate: Equatable {
    var progress: Double
    var direction: Double
}

@MainActor
private final class FakeDebugSession: DebugScrubberSession {
    var preparedIntensities: [Double] = []
    var updates: [DebugUpdate] = []
    var intensities: [Double] = []
    var finishCount = 0
    var prepareError: Error?

    func prepareDebugSession(intensity: Double) async throws {
        if let prepareError { throw prepareError }
        preparedIntensities.append(intensity)
    }
    func updateDebugProgress(_ progress: Double, direction: Double) {
        updates.append(DebugUpdate(progress: progress, direction: direction))
    }
    func updateDebugIntensity(_ intensity: Double) { intensities.append(intensity) }
    func finishDebugSession() async { finishCount += 1 }
}

@MainActor
private final class FakeDebugScheduler: DebugPlaybackScheduling {
    private final class Token: DebugPlaybackCancellation {
        weak var owner: FakeDebugScheduler?
        var isCancelled = false
        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            owner?.cancelCount += 1
            owner?.action = nil
        }
    }

    var action: (@MainActor () -> Void)?
    var scheduleCount = 0
    var cancelCount = 0
    var activeCount: Int { action == nil ? 0 : 1 }

    func schedule(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any DebugPlaybackCancellation {
        scheduleCount += 1
        self.action = action
        let token = Token()
        token.owner = self
        return token
    }

    func fire() { action?() }
}

private final class ClockBox: @unchecked Sendable { var value = 0.0 }
private enum TestDebugError: Error { case expected }
