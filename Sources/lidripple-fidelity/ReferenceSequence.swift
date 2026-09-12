import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

struct ReferenceSequence: Sendable {
    let frames: [PixelFrame]
    let duration: Double

    static func load(
        from url: URL,
        frameCount requestedFrameCount: Int?,
        duration requestedDuration: Double?,
        startTime: Double = 0,
        preferredTimeScale: CMTimeScale? = nil,
        startTimeTicks: Int64? = nil,
        endTimeTicks: Int64? = nil
    ) async throws -> ReferenceSequence {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FidelityError.pathDoesNotExist(url.path)
        }
        if isDirectory.boolValue {
            return try loadDirectory(
                at: url,
                frameCount: requestedFrameCount,
                duration: requestedDuration ?? 0.62
            )
        }

        let videoExtensions = Set(["mov", "mp4", "m4v", "m3u8"])
        guard videoExtensions.contains(url.pathExtension.lowercased()) else {
            throw FidelityError.unsupportedReference(url.path)
        }
        if url.pathExtension.lowercased() == "m3u8" {
            let movie = try LocalHLS.materializeMovie(from: url)
            defer { try? FileManager.default.removeItem(at: movie) }
            return try await loadVideo(
                at: movie,
                frameCount: requestedFrameCount ?? FidelityOptions.defaultVideoFrameCount,
                requestedDuration: requestedDuration,
                startTime: startTime,
                preferredTimeScale: preferredTimeScale,
                startTimeTicks: startTimeTicks,
                endTimeTicks: endTimeTicks
            )
        }
        return try await loadVideo(
            at: url,
            frameCount: requestedFrameCount ?? FidelityOptions.defaultVideoFrameCount,
            requestedDuration: requestedDuration,
            startTime: startTime,
            preferredTimeScale: preferredTimeScale,
            startTimeTicks: startTimeTicks,
            endTimeTicks: endTimeTicks
        )
    }

    private static func loadDirectory(
        at url: URL,
        frameCount: Int?,
        duration: Double
    ) throws -> ReferenceSequence {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { throw FidelityError.noReferenceFrames(url.path) }

        let count = frameCount ?? urls.count
        guard count >= 2 else { throw FidelityError.invalidFrameCount(count) }
        let chosen = (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            let sourceIndex = Int((fraction * Double(urls.count - 1)).rounded())
            return urls[sourceIndex]
        }
        return try ReferenceSequence(
            frames: chosen.map { try PixelFrame.readPNG(at: $0) },
            duration: duration
        )
    }

    private static func loadVideo(
        at url: URL,
        frameCount: Int,
        requestedDuration: Double?,
        startTime: Double,
        preferredTimeScale: CMTimeScale?,
        startTimeTicks: Int64?,
        endTimeTicks: Int64?
    ) async throws -> ReferenceSequence {
        guard frameCount >= 2 else { throw FidelityError.invalidFrameCount(frameCount) }
        let asset = AVURLAsset(url: url)
        let assetDurationTime = try await asset.load(.duration)
        let assetDuration = assetDurationTime.seconds
        guard assetDuration.isFinite, assetDuration > 0 else {
            throw FidelityError.videoHasNoDuration(url.path)
        }
        let availableDuration = assetDuration - startTime
        guard availableDuration > 0 else { throw FidelityError.invalidDuration(availableDuration) }
        let duration = min(requestedDuration ?? availableDuration, availableDuration)
        guard duration > 0 else { throw FidelityError.invalidDuration(duration) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let timeline = try FidelityTimeline(frameCount: frameCount, duration: duration)
        let timeScale = preferredTimeScale ?? assetDurationTime.timescale
        guard timeScale > 0 else {
            throw FidelityError.videoHasNoDuration(url.path)
        }
        let finalSafeTime = max(assetDuration - 1.0 / Double(timeScale), 0)
        var frames: [PixelFrame] = []
        frames.reserveCapacity(frameCount)
        for sample in timeline.samples {
            let requestedTime: CMTime
            if let startTimeTicks, let endTimeTicks {
                let numerator = Double(endTimeTicks - startTimeTicks) * Double(sample.index)
                let denominator = Double(max(frameCount - 1, 1))
                let ticks = startTimeTicks + Int64((numerator / denominator).rounded())
                requestedTime = CMTime(value: ticks, timescale: timeScale)
            } else {
                let seconds = min(startTime + sample.time, finalSafeTime)
                requestedTime = CMTime(seconds: seconds, preferredTimescale: timeScale)
            }
            let result = try await generator.image(at: requestedTime)
            guard result.actualTime == requestedTime else {
                throw FidelityError.videoFrameTimeMismatch(
                    requested: requestedTime.seconds,
                    actual: result.actualTime.seconds
                )
            }
            frames.append(try PixelFrame(image: result.image))
        }
        return ReferenceSequence(frames: frames, duration: duration)
    }
}

enum LocalHLS {
    static func materializeMovie(from playlistURL: URL) throws -> URL {
        let componentURLs = try componentURLs(from: playlistURL)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidripple-hls-\(UUID().uuidString).mp4")
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw FidelityError.invalidLocalHLS(playlistURL.path)
        }
        do {
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            for fragment in componentURLs {
                try handle.write(contentsOf: Data(contentsOf: fragment))
            }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    static func componentURLs(from playlistURL: URL) throws -> [URL] {
        let contents = try String(contentsOf: playlistURL, encoding: .utf8)
        let lines = contents.split(whereSeparator: { $0.isNewline }).map(String.init)
        let mapPrefix = "#EXT-X-MAP:URI=\""
        let mapURI = lines.lazy.compactMap { line -> String? in
            guard line.hasPrefix(mapPrefix), line.hasSuffix("\"") else { return nil }
            return String(line.dropFirst(mapPrefix.count).dropLast())
        }.first
        let segmentURIs = lines.filter { !$0.hasPrefix("#") && !$0.isEmpty }
        guard let mapURI, !segmentURIs.isEmpty else {
            throw FidelityError.invalidLocalHLS(playlistURL.path)
        }

        return try ([mapURI] + segmentURIs).map { component in
            guard !component.contains("://") else {
                throw FidelityError.invalidLocalHLS(playlistURL.path)
            }
            return playlistURL.deletingLastPathComponent()
                .appendingPathComponent(component)
                .standardizedFileURL
        }
    }
}
