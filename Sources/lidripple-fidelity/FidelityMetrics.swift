import Foundation

struct FrameSignal: Codable, Equatable, Sendable {
    let darkBoundary: Double
    let darkBoundaryConfidence: Double
    let edgeEnergy: Double
    let edgeEnergyBands: [Double]
    let edgeSampleFractions: [Double]

    static func measure(_ frame: PixelFrame, mask suppliedMask: PixelMask? = nil) -> FrameSignal {
        let mask = suppliedMask ?? .all(width: frame.width, height: frame.height)
        precondition(mask.width == frame.width && mask.height == frame.height)
        let luminance: [Double] = stride(from: 0, to: frame.bytes.count, by: 4).map { offset in
            let blue = linear(Double(frame.bytes[offset]) / 255)
            let green = linear(Double(frame.bytes[offset + 1]) / 255)
            let red = linear(Double(frame.bytes[offset + 2]) / 255)
            return 0.0722 * blue + 0.7152 * green + 0.2126 * red
        }

        var darkRows = 0
        var boundaryConfidence = 0.0
        for row in stride(from: frame.height - 1, through: 0, by: -1) {
            let start = row * frame.width
            var eligible = 0
            var darkPixels = 0
            for x in 0..<frame.width where mask.contains(x: x, y: row) {
                eligible += 1
                if luminance[start + x] < 0.08 { darkPixels += 1 }
            }
            guard eligible > 0 else { continue }
            let confidence = Double(darkPixels) / Double(eligible)
            guard confidence >= 0.75 else { break }
            boundaryConfidence = min(boundaryConfidence == 0 ? confidence : boundaryConfidence, confidence)
            darkRows += 1
        }

        var sums = [Double](repeating: 0, count: 3)
        var counts = [Int](repeating: 0, count: 3)
        var possible = [Int](repeating: 0, count: 3)
        guard frame.width >= 3, frame.height >= 3 else {
            return FrameSignal(
                darkBoundary: Double(darkRows) / Double(frame.height),
                darkBoundaryConfidence: boundaryConfidence,
                edgeEnergy: 0,
                edgeEnergyBands: [0, 0, 0],
                edgeSampleFractions: [0, 0, 0]
            )
        }
        for y in 1..<(frame.height - 1) {
            let band = min(y * 3 / frame.height, 2)
            for x in 1..<(frame.width - 1) {
                possible[band] += 1
                guard (-1...1).allSatisfy({ dy in
                    (-1...1).allSatisfy { dx in mask.contains(x: x + dx, y: y + dy) }
                }) else { continue }
                let index = y * frame.width + x
                let topLeft = luminance[index - frame.width - 1]
                let top = luminance[index - frame.width]
                let topRight = luminance[index - frame.width + 1]
                let left = luminance[index - 1]
                let right = luminance[index + 1]
                let bottomLeft = luminance[index + frame.width - 1]
                let bottom = luminance[index + frame.width]
                let bottomRight = luminance[index + frame.width + 1]
                let gx = -topLeft + topRight - 2 * left + 2 * right - bottomLeft + bottomRight
                let gy = -topLeft - 2 * top - topRight + bottomLeft + 2 * bottom + bottomRight
                sums[band] += hypot(gx, gy) / (4 * sqrt(2))
                counts[band] += 1
            }
        }
        let bands = zip(sums, counts).map { sum, count in sum / Double(max(count, 1)) }
        return FrameSignal(
            darkBoundary: Double(darkRows) / Double(frame.height),
            darkBoundaryConfidence: boundaryConfidence,
            edgeEnergy: sums.reduce(0, +) / Double(max(counts.reduce(0, +), 1)),
            edgeEnergyBands: bands,
            edgeSampleFractions: zip(counts, possible).map { count, possible in
                Double(count) / Double(max(possible, 1))
            }
        )
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}

struct FidelityMetrics: Codable, Equatable, Sendable {
    struct Frame: Codable, Equatable, Sendable {
        let index: Int
        let progress: Double
        let time: Double
        let reference: FrameSignal
        let rendered: FrameSignal
        let darkBoundaryDifference: Double
        let edgeEnergyDifference: Double
        let referenceEdgeRetentionBands: [Double?]
        let renderedEdgeRetentionBands: [Double?]
    }

    struct Aggregate: Codable, Equatable, Sendable {
        let referenceDarkBoundaryOnsetTime: Double?
        let renderedDarkBoundaryOnsetTime: Double?
        let onsetTimeDifference: Double?
        let meanDarkBoundaryDifference: Double
        let maximumDarkBoundaryDifference: Double
        let meanEdgeEnergyDifference: Double
        let meanEdgeRetentionDifferenceByBand: [Double?]
        let referenceBlurOnsetTimes: [Double?]
        let renderedBlurOnsetTimes: [Double?]
        let normalizedBlurOnsetDifferences: [Double?]
        let referenceDuration: Double
        let candidateDuration: Double
        let durationDifference: Double
        let durationTolerance: Double
        let durationPass: Bool
        let voidPass: Bool?
        let blurPass: Bool?
        let objectivePass: Bool
    }

    let formatVersion: Int
    let note: String
    let duration: Double
    let frames: [Frame]
    let aggregate: Aggregate

    static func make(
        references: [PixelFrame],
        rendered: [PixelFrame],
        timeline: FidelityTimeline,
        candidateDuration: Double? = nil,
        mask: PixelMask? = nil
    ) -> FidelityMetrics {
        precondition(references.count == rendered.count && references.count == timeline.samples.count)
        let referenceSignals = references.map { FrameSignal.measure($0, mask: mask) }
        let renderedSignals = rendered.map { FrameSignal.measure($0, mask: mask) }
        let referenceBaselines = referenceSignals.first?.edgeEnergyBands ?? []
        let renderedBaselines = renderedSignals.first?.edgeEnergyBands ?? []

        let frames = zip(zip(referenceSignals, renderedSignals), timeline.samples).map { pair, sample in
            let reference = pair.0
            let rendered = pair.1
            return Frame(
                index: sample.index,
                progress: sample.progress,
                time: sample.time,
                reference: reference,
                rendered: rendered,
                darkBoundaryDifference: abs(reference.darkBoundary - rendered.darkBoundary),
                edgeEnergyDifference: abs(reference.edgeEnergy - rendered.edgeEnergy),
                referenceEdgeRetentionBands: retention(reference.edgeEnergyBands, baseline: referenceBaselines),
                renderedEdgeRetentionBands: retention(rendered.edgeEnergyBands, baseline: renderedBaselines)
            )
        }

        let referenceDarkOnset = onset(
            in: frames.map(\.reference.darkBoundary),
            samples: timeline.samples
        )
        let renderedDarkOnset = onset(
            in: frames.map(\.rendered.darkBoundary),
            samples: timeline.samples
        )
        let referenceBlurOnsets = (0..<3).map { band in
            retentionOnset(frames.map { $0.referenceEdgeRetentionBands[band] }, samples: timeline.samples)
        }
        let renderedBlurOnsets = (0..<3).map { band in
            retentionOnset(frames.map { $0.renderedEdgeRetentionBands[band] }, samples: timeline.samples)
        }
        let normalizedOnsetDifferences: [Double?] = zip(referenceBlurOnsets, renderedBlurOnsets).map {
            reference, rendered in
            guard let reference, let rendered else { return nil }
            return abs(reference - rendered) / timeline.duration
        }
        let retentionMAE: [Double?] = (0..<3).map { band in
            meanOptional(frames.map { frame in
                guard let lhs = frame.referenceEdgeRetentionBands[band],
                      let rhs = frame.renderedEdgeRetentionBands[band] else { return nil }
                return abs(lhs - rhs)
            })
        }

        let darkDifferences = frames.map(\.darkBoundaryDifference)
        let referenceBoundaryRange = range(referenceSignals.map(\.darkBoundary))
        let resolvedCandidateDuration = candidateDuration ?? timeline.candidateDuration
        let frameInterval = timeline.duration / Double(max(timeline.samples.count - 1, 1))
        let durationTolerance = max(frameInterval, 1.0 / 60.0)
        let durationDifference = abs(timeline.duration - resolvedCandidateDuration)
        let durationPass = durationDifference <= durationTolerance
        let horizonConfident = referenceSignals.contains {
            $0.darkBoundary > 0 && $0.darkBoundaryConfidence >= 0.75
        }
        let voidPass: Bool? = referenceBoundaryRange >= 0.02 && horizonConfident
            ? mean(darkDifferences) <= 0.04 && (darkDifferences.max() ?? 0) <= 0.08
            : nil
        let blurCoverageSufficient = referenceSignals.allSatisfy {
            $0.edgeSampleFractions.allSatisfy { $0 >= 0.20 }
        }
        let blurEvidenceComplete = blurCoverageSufficient
            && normalizedOnsetDifferences.allSatisfy { $0 != nil }
            && retentionMAE.allSatisfy { $0 != nil }
        let blurPass: Bool? = blurEvidenceComplete
            ? normalizedOnsetDifferences.allSatisfy { ($0 ?? .infinity) <= 0.08 }
                && retentionMAE.allSatisfy { ($0 ?? .infinity) <= 0.10 }
            : nil

        return FidelityMetrics(
            formatVersion: 2,
            note: "Linear-light diagnostic curves. Missing void/blur evidence is unavailable, never coerced to a pass; human review is still required for S6.",
            duration: timeline.duration,
            frames: frames,
            aggregate: Aggregate(
                referenceDarkBoundaryOnsetTime: referenceDarkOnset,
                renderedDarkBoundaryOnsetTime: renderedDarkOnset,
                onsetTimeDifference: referenceDarkOnset.flatMap { reference in
                    renderedDarkOnset.map { abs(reference - $0) }
                },
                meanDarkBoundaryDifference: mean(darkDifferences),
                maximumDarkBoundaryDifference: darkDifferences.max() ?? 0,
                meanEdgeEnergyDifference: mean(frames.map(\.edgeEnergyDifference)),
                meanEdgeRetentionDifferenceByBand: retentionMAE,
                referenceBlurOnsetTimes: referenceBlurOnsets,
                renderedBlurOnsetTimes: renderedBlurOnsets,
                normalizedBlurOnsetDifferences: normalizedOnsetDifferences,
                referenceDuration: timeline.duration,
                candidateDuration: resolvedCandidateDuration,
                durationDifference: durationDifference,
                durationTolerance: durationTolerance,
                durationPass: durationPass,
                voidPass: voidPass,
                blurPass: blurPass,
                objectivePass: durationPass && voidPass == true && blurPass == true
            )
        )
    }

    private static func retention(_ values: [Double], baseline: [Double]) -> [Double?] {
        zip(values, baseline).map { value, baseline in
            baseline > 0.000_1 ? value / baseline : nil
        }
    }

    private static func retentionOnset(
        _ values: [Double?],
        samples: [FidelityTimeline.Sample]
    ) -> Double? {
        zip(values, samples).first { value, _ in
            guard let value else { return false }
            return value < 0.90
        }?.1.time
    }

    private static func onset(
        in values: [Double],
        samples: [FidelityTimeline.Sample]
    ) -> Double? {
        guard let baseline = values.first else { return nil }
        return zip(values, samples).first { abs($0.0 - baseline) >= 0.02 }?.1.time
    }

    private static func range(_ values: [Double]) -> Double {
        guard let minimum = values.min(), let maximum = values.max() else { return 0 }
        return maximum - minimum
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(max(values.count, 1))
    }

    private static func meanOptional(_ values: [Double?]) -> Double? {
        let valid = values.compactMap { $0 }
        return valid.isEmpty ? nil : mean(valid)
    }
}
