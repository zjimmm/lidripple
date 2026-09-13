import Foundation

enum FidelityDirection: String, Codable, Equatable, Sendable {
    case closing
    case opening
}

enum FidelityCurve: String, Codable, Equatable, Sendable {
    case linear
    case smoothstep
}

struct FidelityOptions: Equatable {
    static let defaultVideoFrameCount = 38

    let referenceURL: URL
    let outputDirectory: URL
    let frameCount: Int?
    let duration: Double?
    let startTime: Double
    let direction: FidelityDirection
    let curve: FidelityCurve
    let tuningURL: URL?
    let referenceManifestURL: URL?
    let privateReference: Bool

    static let usage = """
    Usage: lidripple-fidelity --reference <directory|video> \\
             --output-dir <directory> [--frames <count>] [--start-time <seconds>] \\
             [--duration <seconds>] [--direction <closing|opening>] \
             [--curve <linear|smoothstep>] [--tuning <json>] \
             [--reference-manifest <json>] [--private-reference]

    Produces rendered/, reference/, comparison/, comparison.gif, contact-sheet.png,
    metrics.json, and manifest.json. Directories are read as lexically sorted PNG sequences. Video
    inputs may be MOV, MP4, M4V, or a local M3U8 HLS playlist. Each comparison places
    the reference on the left and lidripple render on the right.
    """

    static func parse(_ arguments: [String], currentDirectory: URL) throws -> FidelityOptions {
        var values: [String: String] = [:]
        var index = 0
        let valueOptions = Set([
            "--reference", "--output-dir", "--frames", "--duration", "--start-time",
            "--direction", "--curve", "--tuning", "--reference-manifest",
        ])
        let flagOptions = Set(["--private-reference"])
        var flags: Set<String> = []

        while index < arguments.count {
            let option = arguments[index]
            if option == "--help" || option == "-h" { throw FidelityError.helpRequested }
            if flagOptions.contains(option) {
                flags.insert(option)
                index += 1
                continue
            }
            guard valueOptions.contains(option) else { throw FidelityError.unknownOption(option) }
            let valueIndex = index + 1
            guard valueIndex < arguments.count else { throw FidelityError.missingValue(option) }
            let value = arguments[valueIndex]
            guard !value.hasPrefix("--") else { throw FidelityError.missingValue(option) }
            values[option] = value
            index += 2
        }

        func required(_ option: String) throws -> String {
            guard let value = values[option] else { throw FidelityError.missingOption(option) }
            return value
        }
        func url(_ value: String, isDirectory: Bool = false) -> URL {
            if value.hasPrefix("/") { return URL(fileURLWithPath: value, isDirectory: isDirectory) }
            return currentDirectory.appendingPathComponent(value, isDirectory: isDirectory)
        }

        let reference = try url(required("--reference"))
        let output = try url(required("--output-dir"), isDirectory: true)
        let frameCount: Int?
        if let raw = values["--frames"] {
            guard let parsed = Int(raw) else {
                throw FidelityError.invalidInteger(option: "--frames", value: raw)
            }
            guard parsed >= 2 else { throw FidelityError.invalidFrameCount(parsed) }
            frameCount = parsed
        } else {
            frameCount = nil
        }
        let duration: Double?
        if let raw = values["--duration"] {
            guard let parsed = Double(raw) else {
                throw FidelityError.invalidNumber(option: "--duration", value: raw)
            }
            guard parsed > 0 else { throw FidelityError.invalidDuration(parsed) }
            duration = parsed
        } else {
            duration = nil
        }
        let startTime: Double
        if let raw = values["--start-time"] {
            guard let parsed = Double(raw) else {
                throw FidelityError.invalidNumber(option: "--start-time", value: raw)
            }
            guard parsed >= 0 else { throw FidelityError.invalidStartTime(parsed) }
            startTime = parsed
        } else {
            startTime = 0
        }
        let direction: FidelityDirection
        if let raw = values["--direction"] {
            guard let parsed = FidelityDirection(rawValue: raw) else {
                throw FidelityError.invalidDirection(raw)
            }
            direction = parsed
        } else {
            direction = .closing
        }
        let curve: FidelityCurve
        if let raw = values["--curve"] {
            guard let parsed = FidelityCurve(rawValue: raw) else {
                throw FidelityError.invalidCurve(raw)
            }
            curve = parsed
        } else {
            curve = .linear
        }
        let tuningURL = values["--tuning"].map { url($0).standardizedFileURL }
        let referenceManifestURL = values["--reference-manifest"].map {
            url($0).standardizedFileURL
        }

        return FidelityOptions(
            referenceURL: reference.standardizedFileURL,
            outputDirectory: output.standardizedFileURL,
            frameCount: frameCount,
            duration: duration,
            startTime: startTime,
            direction: direction,
            curve: curve,
            tuningURL: tuningURL,
            referenceManifestURL: referenceManifestURL,
            privateReference: flags.contains("--private-reference")
        )
    }
}
