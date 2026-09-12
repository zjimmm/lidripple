import Foundation
import ImageIO
import UniformTypeIdentifiers
import LidRippleCore

enum FidelityTool {
    static let name = "lidripple-fidelity"
    static let version = "1.0.0"
}

struct FidelityManifest: Codable, Equatable {
    struct Tool: Codable, Equatable {
        let name: String
        let version: String
    }

    struct Provenance: Codable, Equatable {
        let sourceSHA256: String
        let referenceSHA256: String
        let tuningSHA256: String
        let tuning: String
        let referenceManifestSHA256: String?
        let referenceRights: String
    }

    let formatVersion: Int
    let tool: Tool
    let provenance: Provenance
    let layout: String
    let direction: FidelityDirection
    let curve: FidelityCurve
    let width: Int
    let height: Int
    let duration: Double
    let candidateDuration: Double
    let referenceStartTime: Double
    let samples: [FidelityTimeline.Sample]
}

enum FidelityRun {
    static func execute(options: FidelityOptions) async throws {
        try prepareOutputDirectory(options.outputDirectory)
        let tuning = try options.tuningURL.map { try FoldTuning.loading(overridesAt: $0) } ?? .default
        let tuningData: Data
        if let tuningURL = options.tuningURL {
            tuningData = try Data(contentsOf: tuningURL)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            tuningData = try encoder.encode(tuning)
        }
        let referenceManifest = try ReferenceValidation.validate(
            referenceURL: options.referenceURL,
            manifestURL: options.referenceManifestURL,
            startTime: options.startTime,
            duration: options.duration,
            privateReference: options.privateReference
        )
        let references = try await ReferenceSequence.load(
            from: options.referenceURL,
            frameCount: options.frameCount,
            duration: options.duration,
            startTime: options.startTime,
            preferredTimeScale: referenceManifest?.technical.presentationTimeScale,
            startTimeTicks: referenceManifest?.transition.anchors.foldStart.presentationTimeTicks,
            endTimeTicks: referenceManifest?.transition.anchors.foldComplete.presentationTimeTicks
        )
        let alignedReferences: [PixelFrame]
        let measurementMask: PixelMask
        if let alignment = referenceManifest?.alignment {
            alignedReferences = try references.frames.map(alignment.correct)
            measurementMask = alignment.measurementMask()
        } else {
            alignedReferences = references.frames
            measurementMask = PixelMask.all(
                width: alignedReferences[0].width,
                height: alignedReferences[0].height
            )
        }
        let source = alignedReferences[0]
        let timeline = try FidelityTimeline(
            frameCount: alignedReferences.count,
            duration: references.duration,
            candidateDuration: tuning.scriptedUnfoldSeconds,
            direction: options.direction,
            curve: options.curve
        )
        let renderer = try FidelityFrameRenderer(tuning: tuning)
        try renderer.installSource(source)

        let renderedDirectory = options.outputDirectory.appendingPathComponent("rendered", isDirectory: true)
        let referenceDirectory = options.outputDirectory.appendingPathComponent("reference", isDirectory: true)
        let comparisonDirectory = options.outputDirectory.appendingPathComponent("comparison", isDirectory: true)
        let referenceDiagnosticsDirectory = options.outputDirectory
            .appendingPathComponent("diagnostics-reference", isDirectory: true)
        let renderedDiagnosticsDirectory = options.outputDirectory
            .appendingPathComponent("diagnostics-rendered", isDirectory: true)
        for directory in [
            renderedDirectory,
            referenceDirectory,
            comparisonDirectory,
            referenceDiagnosticsDirectory,
            renderedDiagnosticsDirectory,
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var comparisons: [PixelFrame] = []
        var normalizedReferences: [PixelFrame] = []
        var renderedFrames: [PixelFrame] = []
        comparisons.reserveCapacity(timeline.samples.count)
        normalizedReferences.reserveCapacity(timeline.samples.count)
        renderedFrames.reserveCapacity(timeline.samples.count)
        for (sample, reference) in zip(timeline.samples, alignedReferences) {
            let rendered = try renderer.render(
                progress: sample.progress,
                width: source.width,
                height: source.height
            )
            let comparison = try ComparisonCanvas.make(
                reference: reference,
                rendered: rendered,
                progress: sample.progress,
                time: sample.time,
                duration: timeline.duration
            )
            let name = String(format: "frame-%04d.png", sample.index)
            try rendered.writePNG(to: renderedDirectory.appendingPathComponent(name))
            try reference.writePNG(to: referenceDirectory.appendingPathComponent(name))
            try comparison.writePNG(to: comparisonDirectory.appendingPathComponent(name))
            normalizedReferences.append(reference)
            renderedFrames.append(rendered)
            comparisons.append(comparison)
        }

        try writeGIF(
            frames: comparisons,
            duration: timeline.duration,
            to: options.outputDirectory.appendingPathComponent("comparison.gif")
        )
        let thumbnailWidth = min(comparisons[0].width, 640)
        let thumbnailHeight = max(
            Int((Double(comparisons[0].height) * Double(thumbnailWidth)
                / Double(comparisons[0].width)).rounded()),
            1
        )
        let thumbnails = try comparisons.map {
            try $0.resized(width: thumbnailWidth, height: thumbnailHeight)
        }
        try PixelFrame.contactSheet(frames: thumbnails).writePNG(
            to: options.outputDirectory.appendingPathComponent("contact-sheet.png")
        )
        let metrics = FidelityMetrics.make(
            references: normalizedReferences,
            rendered: renderedFrames,
            timeline: timeline,
            candidateDuration: tuning.scriptedUnfoldSeconds,
            mask: measurementMask
        )
        for (index, frameMetrics) in metrics.frames.enumerated() {
            let name = String(format: "frame-%04d.png", index)
            try DiagnosticOverlay.make(
                frame: normalizedReferences[index],
                signal: frameMetrics.reference,
                mask: measurementMask
            ).writePNG(to: referenceDiagnosticsDirectory.appendingPathComponent(name))
            try DiagnosticOverlay.make(
                frame: renderedFrames[index],
                signal: frameMetrics.rendered,
                mask: measurementMask
            ).writePNG(to: renderedDiagnosticsDirectory.appendingPathComponent(name))
        }
        try writeJSON(
            metrics,
            to: options.outputDirectory.appendingPathComponent("metrics.json")
        )
        let manifest = FidelityManifest(
            formatVersion: 2,
            tool: .init(name: FidelityTool.name, version: FidelityTool.version),
            provenance: .init(
                sourceSHA256: ArtifactHash.sha256(data: Data(source.bytes)),
                referenceSHA256: try ArtifactHash.sha256(url: options.referenceURL),
                tuningSHA256: ArtifactHash.sha256(data: tuningData),
                tuning: options.tuningURL?.lastPathComponent ?? "built-in defaults",
                referenceManifestSHA256: try options.referenceManifestURL.map {
                    try ArtifactHash.sha256(url: $0)
                },
                referenceRights: referenceManifest.map {
                    $0.permitsRedistribution ? "redistribution-established" : "private-analysis-only"
                } ?? "synthetic-directory"
            ),
            layout: "labeled reference-left, lidripple-right; synchronized ruler below",
            direction: options.direction,
            curve: options.curve,
            width: source.width,
            height: source.height,
            duration: timeline.duration,
            candidateDuration: timeline.candidateDuration,
            referenceStartTime: options.startTime,
            samples: timeline.samples
        )
        try writeJSON(
            manifest,
            to: options.outputDirectory.appendingPathComponent("manifest.json")
        )
    }

    static func writeGIF(frames: [PixelFrame], duration: Double, to url: URL) throws {
        guard !frames.isEmpty,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.gif.identifier as CFString,
                frames.count,
                nil
              ) else { throw FidelityError.imageWriteFailed(url.path) }
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0] as CFDictionary,
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let delay = duration / Double(max(frames.count - 1, 1))
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay] as CFDictionary,
        ]
        for frame in frames {
            CGImageDestinationAddImage(
                destination,
                try frame.makeImage(),
                frameProperties as CFDictionary
            )
        }
        guard CGImageDestinationFinalize(destination) else {
            throw FidelityError.imageWriteFailed(url.path)
        }
    }

    static func prepareOutputDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw FidelityError.outputDirectoryNotEmpty(directory.path)
            }
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
            guard contents.isEmpty else {
                throw FidelityError.outputDirectoryNotEmpty(directory.path)
            }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
