import LidRippleCore

/// Seven 16-byte vectors keep the Swift and Metal layouts identical without
/// relying on compiler-specific padding between scalar and vector fields.
struct FoldUniforms: Equatable, Sendable {
    /// progress, squash exponent gain, rotation radians, field-of-view radians
    var geometry: SIMD4<Float>
    /// eye distance, eye vertical offset, max blur radius, blur progress exponent
    var cameraAndBlur: SIMD4<Float>
    /// void speed, void softness, rim width, rim intensity
    var voidAndRim: SIMD4<Float>
    /// rim widening, cool tint strength, vignette strength, dither amplitude
    var finish: SIMD4<Float>
    /// viewport width/height, source width/height
    var dimensions: SIMD4<Float>
    /// warm-black RGB, blur extra-tap distance
    var colorAndTap: SIMD4<Float>
    /// reduced-quality flag, geometry progress exponent, seal fade start, reserved
    var quality: SIMD4<Float>

    static func make(
        progress: Double,
        tuning: FoldTuning,
        viewportSize: SIMD2<Int>,
        sourceSize: SIMD2<Int>,
        reducedQuality: Bool = false
    ) -> FoldUniforms {
        let clampedProgress = min(max(progress, 0), tuning.maxProgress)
        let degreesToRadians = Float.pi / 180

        return FoldUniforms(
            geometry: SIMD4<Float>(
                Float(clampedProgress),
                Float(tuning.squashExponentGain),
                Float(tuning.rotationDegrees) * degreesToRadians,
                Float(tuning.fieldOfViewDegrees) * degreesToRadians
            ),
            cameraAndBlur: SIMD4<Float>(
                Float(tuning.eyeDistanceScreenHeights),
                Float(tuning.eyeVerticalOffset),
                Float(tuning.blurRadiusPx),
                Float(tuning.blurProgressExponent)
            ),
            voidAndRim: SIMD4<Float>(
                Float(tuning.voidSpeed),
                Float(tuning.voidSoftness),
                Float(tuning.rimWidth),
                Float(tuning.rimIntensity)
            ),
            finish: SIMD4<Float>(
                Float(tuning.rimWidening),
                Float(tuning.coolTintStrength),
                Float(tuning.vignetteStrength),
                Float(tuning.ditherAmplitude)
            ),
            dimensions: SIMD4<Float>(
                Float(max(viewportSize.x, 1)),
                Float(max(viewportSize.y, 1)),
                Float(max(sourceSize.x, 1)),
                Float(max(sourceSize.y, 1))
            ),
            colorAndTap: SIMD4<Float>(
                Float(tuning.warmBlackRed),
                Float(tuning.warmBlackGreen),
                Float(tuning.warmBlackBlue),
                Float(tuning.blurExtraTapDistance)
            ),
            quality: SIMD4<Float>(
                reducedQuality ? 1 : 0,
                Float(tuning.geometryProgressExponent),
                Float(tuning.sealFadeStart),
                0
            )
        )
    }
}
