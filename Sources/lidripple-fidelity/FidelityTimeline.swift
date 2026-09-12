import Foundation

struct FidelityTimeline: Equatable, Sendable {
    struct Sample: Codable, Equatable, Sendable {
        let index: Int
        let progress: Double
        let time: Double
    }

    let duration: Double
    let candidateDuration: Double
    let direction: FidelityDirection
    let curve: FidelityCurve
    let samples: [Sample]

    init(
        frameCount: Int,
        duration: Double,
        candidateDuration: Double? = nil,
        direction: FidelityDirection = .closing,
        curve: FidelityCurve = .linear
    ) throws {
        guard frameCount >= 2 else { throw FidelityError.invalidFrameCount(frameCount) }
        guard duration > 0 else { throw FidelityError.invalidDuration(duration) }
        let resolvedCandidateDuration = candidateDuration ?? duration
        guard resolvedCandidateDuration > 0 else {
            throw FidelityError.invalidDuration(resolvedCandidateDuration)
        }
        self.duration = duration
        self.candidateDuration = resolvedCandidateDuration
        self.direction = direction
        self.curve = curve
        samples = (0..<frameCount).map { index in
            let fraction = Double(index) / Double(frameCount - 1)
            let time = fraction * duration
            let candidateFraction = min(max(time / resolvedCandidateDuration, 0), 1)
            let curved: Double
            switch curve {
            case .linear:
                curved = candidateFraction
            case .smoothstep:
                curved = candidateFraction * candidateFraction * (3 - 2 * candidateFraction)
            }
            let progress = direction == .closing ? curved : 1 - curved
            return Sample(index: index, progress: progress, time: time)
        }
    }
}
