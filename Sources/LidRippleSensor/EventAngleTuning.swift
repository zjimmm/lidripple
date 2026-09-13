import Foundation
import LidRippleCore

/// Timing for the sensor-less close program.
///
/// The landmarks are expressed as fractions of the whole program. `duration`
/// is the visible folding interval, from the fold-start landmark to the seal;
/// the arm/warmup lead-in is additional time. Angles are derived from
/// `FoldTuning`; this type never duplicates phase thresholds.
public struct EventAngleTuning: Codable, Equatable, Sendable {
    public var duration: TimeInterval
    public var framesPerSecond: Double
    public var armFraction: Double
    public var foldStartFraction: Double
    public var foldEndFraction: Double

    public init(
        duration: TimeInterval = 0.550,
        framesPerSecond: Double = 60,
        armFraction: Double = 0.14,
        foldStartFraction: Double = 0.34,
        foldEndFraction: Double = 0.86
    ) {
        self.duration = duration
        self.framesPerSecond = framesPerSecond
        self.armFraction = armFraction
        self.foldStartFraction = foldStartFraction
        self.foldEndFraction = foldEndFraction
    }

    public static let `default` = EventAngleTuning()

    /// Full angle program including the arm and speculative-capture lead-in.
    public var programDuration: TimeInterval {
        duration / (1 - foldStartFraction)
    }

    func validated() throws -> EventAngleTuning {
        guard duration.isFinite, duration > 0,
              framesPerSecond.isFinite, framesPerSecond > 0,
              armFraction > 0,
              armFraction < foldStartFraction,
              foldStartFraction < foldEndFraction,
              foldEndFraction < 1,
              programDuration.isFinite,
              programDuration * framesPerSecond < Double(Int.max - 2)
        else { throw EventAngleSourceError.invalidTuning }
        return self
    }

    func angle(at fraction: Double, fold: FoldTuning) -> Double {
        let startAngle = max(fold.armAngle + 15, fold.idleReturnAngle + 5)
        let armedAngle = fold.armAngle - 1
        let foldingAngle = fold.foldStartAngle - 1
        let foldedAngle = fold.foldEndAngle - 1
        let sealedAngle = max(fold.sealAngle - 1, 0)

        if fraction <= armFraction {
            return interpolate(startAngle, armedAngle, fraction / armFraction)
        }
        if fraction <= foldStartFraction {
            return interpolate(
                armedAngle,
                foldingAngle,
                (fraction - armFraction) / (foldStartFraction - armFraction)
            )
        }
        if fraction <= foldEndFraction {
            return interpolate(
                foldingAngle,
                foldedAngle,
                (fraction - foldStartFraction) / (foldEndFraction - foldStartFraction)
            )
        }
        return interpolate(
            foldedAngle,
            sealedAngle,
            (fraction - foldEndFraction) / (1 - foldEndFraction)
        )
    }

    private func interpolate(_ start: Double, _ end: Double, _ fraction: Double) -> Double {
        start + (end - start) * min(max(fraction, 0), 1)
    }
}
