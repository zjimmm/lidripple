import Foundation

public enum FoldTuningError: Error, Equatable {
    case unknownKey(String)
}

/// Every tunable constant in lidripple, in one place.
///
/// Spec section 9.4 requires this: tuning the animation must be a data change,
/// not a rebuild. No other type in the package may hard-code any of these.
public struct FoldTuning: Codable, Equatable, Sendable {
    // MARK: Phase thresholds (degrees)
    public var armAngle: Double = 110
    public var foldStartAngle: Double = 75
    public var foldEndAngle: Double = 25
    public var sealAngle: Double = 12
    public var idleReturnAngle: Double = 78
    /// Gap between fold entry (75) and idle return (78). Spec section 9.2.
    public var phaseHysteresisDegrees: Double = 3

    // MARK: Direction detection
    public var directionVelocityThreshold: Double = 5      // degrees/second
    public var directionHoldSeconds: Double = 0.050
    /// Net travel required to commit a direction. Plan deviation 2.
    public var directionMinTravelDegrees: Double = 0.8

    // MARK: Filtering
    public var filterCutoffHz: Double = 15
    /// Velocity smoothing. Plan deviation 1.
    /// Empirically lowered from spec's 8 Hz to keep jitterAtRestKeepsSmoothedVelocityBelowTheDirectionGate passing with margin.
    public var velocitySmoothingHz: Double = 4.0
    public var deadbandDegrees: Double = 0.3

    // MARK: Spring
    public var stiffness: Double = 220
    public var damping: Double = 26
    public var feedForward: Double = 0.06
    public var maxProgress: Double = 1.06
    public var substepSeconds: Double = 1.0 / 240.0
    /// Below this, the spring is considered at rest for phase-transition purposes
    /// (e.g. unfolding -> idle). A numerical epsilon, not a feel-tuning knob.
    public var springSettleEpsilon: Double = 0.001

    // MARK: Post-unlock unfold (spec FR-10)
    public var scriptedUnfoldSeconds: Double = 0.620
    /// An observed fully-open M4 lid reads about 100°, below `armAngle`.
    /// Sensor-paced reveals reach zero by this angle; timed fallback ignores it.
    public var openingTrackEndAngle: Double = 95
    /// Rounds whole-degree HID steps into display-rate motion without letting
    /// the reveal get ahead of the measured opening angle.
    public var openingTrackSmoothingSeconds: Double = 0.050
    /// Give the post-unlock HID source a brief chance to report the current
    /// lid pose before displaying a fresh fold frame.
    public var openingFirstSampleWaitSeconds: Double = 0.120
    /// Stop waiting for a stalled or stale sensor after this many seconds.
    /// Its constraint then fades out over `scriptedUnfoldSeconds`.
    public var openingTrackHoldSeconds: Double = 2.0

    // MARK: Render (consumed in Plan 2; defined here so section 9.4 holds)
    /// Delays the screen-space collapse so content remains legible through mid-close.
    public var geometryProgressExponent: Double = 3.0
    public var squashExponentGain: Double = 1.8
    public var rotationDegrees: Double = 72
    public var blurRadiusPx: Double = 28
    public var blurProgressExponent: Double = 2.0
    /// Keeps the dark boundary close to the hinge instead of climbing the panel.
    public var voidSpeed: Double = 0.055
    public var voidSoftness: Double = 0.09
    /// Background and folded panel reach warm-black only near the final seal.
    public var sealFadeStart: Double = 0.88
    public var rimWidth: Double = 0.012
    public var rimIntensity: Double = 0.35
    public var rimWidening: Double = 1.8
    public var fieldOfViewDegrees: Double = 38
    public var eyeDistanceScreenHeights: Double = 1.1
    public var eyeVerticalOffset: Double = 0.06
    public var warmBlackRed: Double = 0.012
    public var warmBlackGreen: Double = 0.009
    public var warmBlackBlue: Double = 0.015
    public var coolTintStrength: Double = 0.08
    public var vignetteStrength: Double = 0.18
    public var ditherAmplitude: Double = 1.5 / 255.0
    public var blurExtraTapDistance: Double = 0.65

    // MARK: User control
    public var intensity: Double = 1.0

    public init() {}

    public static let `default` = FoldTuning()

    /// Applies the user intensity control. Spec FR-17: scales exactly blur
    /// radius, rotation, and squash exponent; never timing, thresholds, or
    /// the spring.
    public func withIntensity(_ intensity: Double) -> FoldTuning {
        let clamped = min(max(intensity, 0.5), 1.0)
        var copy = self
        copy.intensity = clamped
        copy.blurRadiusPx = self.blurRadiusPx * clamped
        copy.rotationDegrees = self.rotationDegrees * clamped
        copy.squashExponentGain = self.squashExponentGain * clamped
        return copy
    }

    /// Applies a sparse set of overrides, e.g. from a hot-reloaded JSON file.
    /// Unknown keys throw rather than being ignored, so a typo in a tuning
    /// file surfaces immediately instead of silently doing nothing.
    public mutating func apply(overrides: [String: Double]) throws {
        for (key, value) in overrides {
            switch key {
            case "armAngle": armAngle = value
            case "foldStartAngle": foldStartAngle = value
            case "foldEndAngle": foldEndAngle = value
            case "sealAngle": sealAngle = value
            case "idleReturnAngle": idleReturnAngle = value
            case "phaseHysteresisDegrees": phaseHysteresisDegrees = value
            case "directionVelocityThreshold": directionVelocityThreshold = value
            case "directionHoldSeconds": directionHoldSeconds = value
            case "directionMinTravelDegrees": directionMinTravelDegrees = value
            case "filterCutoffHz": filterCutoffHz = value
            case "velocitySmoothingHz": velocitySmoothingHz = value
            case "deadbandDegrees": deadbandDegrees = value
            case "stiffness": stiffness = value
            case "damping": damping = value
            case "feedForward": feedForward = value
            case "maxProgress": maxProgress = value
            case "substepSeconds": substepSeconds = value
            case "springSettleEpsilon": springSettleEpsilon = value
            case "scriptedUnfoldSeconds": scriptedUnfoldSeconds = value
            case "openingTrackEndAngle": openingTrackEndAngle = value
            case "openingTrackSmoothingSeconds": openingTrackSmoothingSeconds = value
            case "openingFirstSampleWaitSeconds": openingFirstSampleWaitSeconds = value
            case "openingTrackHoldSeconds": openingTrackHoldSeconds = value
            case "geometryProgressExponent": geometryProgressExponent = value
            case "squashExponentGain": squashExponentGain = value
            case "rotationDegrees": rotationDegrees = value
            case "blurRadiusPx": blurRadiusPx = value
            case "blurProgressExponent": blurProgressExponent = value
            case "voidSpeed": voidSpeed = value
            case "voidSoftness": voidSoftness = value
            case "sealFadeStart": sealFadeStart = value
            case "rimWidth": rimWidth = value
            case "rimIntensity": rimIntensity = value
            case "rimWidening": rimWidening = value
            case "fieldOfViewDegrees": fieldOfViewDegrees = value
            case "eyeDistanceScreenHeights": eyeDistanceScreenHeights = value
            case "eyeVerticalOffset": eyeVerticalOffset = value
            case "warmBlackRed": warmBlackRed = value
            case "warmBlackGreen": warmBlackGreen = value
            case "warmBlackBlue": warmBlackBlue = value
            case "coolTintStrength": coolTintStrength = value
            case "vignetteStrength": vignetteStrength = value
            case "ditherAmplitude": ditherAmplitude = value
            case "blurExtraTapDistance": blurExtraTapDistance = value
            case "intensity": intensity = value
            default: throw FoldTuningError.unknownKey(key)
            }
        }
    }

    /// Loads defaults with a JSON override file applied on top.
    public static func loading(overridesAt url: URL) throws -> FoldTuning {
        let data = try Data(contentsOf: url)
        let overrides = try JSONDecoder().decode([String: Double].self, from: data)
        var tuning = FoldTuning.default
        try tuning.apply(overrides: overrides)
        return tuning
    }
}
