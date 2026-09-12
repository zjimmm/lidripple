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

    // MARK: Scripted unfold on unlock (spec FR-10)
    public var scriptedUnfoldSeconds: Double = 0.620

    // MARK: Render (consumed in Plan 2; defined here so section 9.4 holds)
    public var squashExponentGain: Double = 1.8
    public var rotationDegrees: Double = 72
    public var blurRadiusPx: Double = 28
    public var blurProgressExponent: Double = 2.0
    public var voidSpeed: Double = 1.15
    public var voidSoftness: Double = 0.28
    public var rimWidth: Double = 0.012
    public var rimIntensity: Double = 0.35

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
        copy.blurRadiusPx = FoldTuning.default.blurRadiusPx * clamped
        copy.rotationDegrees = FoldTuning.default.rotationDegrees * clamped
        copy.squashExponentGain = FoldTuning.default.squashExponentGain * clamped
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
            case "scriptedUnfoldSeconds": scriptedUnfoldSeconds = value
            case "squashExponentGain": squashExponentGain = value
            case "rotationDegrees": rotationDegrees = value
            case "blurRadiusPx": blurRadiusPx = value
            case "blurProgressExponent": blurProgressExponent = value
            case "voidSpeed": voidSpeed = value
            case "voidSoftness": voidSoftness = value
            case "rimWidth": rimWidth = value
            case "rimIntensity": rimIntensity = value
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
