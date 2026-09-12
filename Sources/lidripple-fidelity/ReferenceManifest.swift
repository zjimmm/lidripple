import Foundation

struct ReferenceManifest: Decodable, Sendable {
    struct Source: Decodable, Sendable {
        struct Rights: Decodable, Sendable {
            let copyrightHolder: String
            let licenseIdentifier: String?
            let redistributionAndDerivativePermission: String
        }

        let title: String
        let publisher: String
        let analyzedVariantURL: URL
        let rights: Rights
    }

    struct AnalysisCopy: Decodable, Sendable {
        let sha256: String
    }

    struct Technical: Decodable, Sendable {
        let presentationTimeScale: Int32
    }

    struct Transition: Decodable, Sendable {
        struct Anchor: Decodable, Sendable {
            let presentationTimeTicks: Int64
            let presentationTimeSeconds: Double
        }

        struct Anchors: Decodable, Sendable {
            let foldStart: Anchor
            let foldComplete: Anchor
        }

        let anchors: Anchors
    }

    let schemaVersion: Int
    let source: Source
    let analysisCopy: AnalysisCopy
    let technical: Technical
    let transition: Transition
    let alignment: PanelAlignment?

    var permitsRedistribution: Bool {
        source.rights.redistributionAndDerivativePermission == "established"
            && source.rights.licenseIdentifier?.isEmpty == false
    }

    static func load(at url: URL) throws -> ReferenceManifest {
        let manifest: ReferenceManifest
        do {
            manifest = try JSONDecoder().decode(
                ReferenceManifest.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw FidelityError.invalidReferenceManifest(error.localizedDescription)
        }
        try manifest.validate()
        return manifest
    }

    func validate() throws {
        guard schemaVersion == 1 else {
            throw FidelityError.invalidReferenceManifest("unsupported schemaVersion \(schemaVersion)")
        }
        guard !source.title.isEmpty, !source.publisher.isEmpty,
              !source.rights.copyrightHolder.isEmpty else {
            throw FidelityError.invalidReferenceManifest("source attribution is incomplete")
        }
        guard analysisCopy.sha256.count == 64,
              analysisCopy.sha256.allSatisfy({ $0.isHexDigit }) else {
            throw FidelityError.invalidReferenceManifest("analysisCopy.sha256 is not SHA-256")
        }
        guard technical.presentationTimeScale > 0 else {
            throw FidelityError.invalidReferenceManifest("presentationTimeScale must be positive")
        }
        let start = transition.anchors.foldStart
        let complete = transition.anchors.foldComplete
        guard start.presentationTimeTicks >= 0,
              complete.presentationTimeTicks > start.presentationTimeTicks else {
            throw FidelityError.invalidReferenceManifest("fold anchors are invalid")
        }
        let scale = Double(technical.presentationTimeScale)
        guard abs(Double(start.presentationTimeTicks) / scale - start.presentationTimeSeconds) < 1e-9,
              abs(Double(complete.presentationTimeTicks) / scale - complete.presentationTimeSeconds) < 1e-9 else {
            throw FidelityError.invalidReferenceManifest("anchor seconds do not match their exact ticks")
        }
    }
}

enum ReferenceValidation {
    static func validate(
        referenceURL: URL,
        manifestURL: URL?,
        startTime: Double,
        duration: Double?,
        privateReference: Bool
    ) throws -> ReferenceManifest? {
        let videoExtensions = Set(["mov", "mp4", "m4v", "m3u8"])
        guard videoExtensions.contains(referenceURL.pathExtension.lowercased()) else {
            return nil
        }
        guard let manifestURL else { throw FidelityError.referenceManifestRequired }
        let manifest = try ReferenceManifest.load(at: manifestURL)
        guard let alignment = manifest.alignment else {
            throw FidelityError.invalidReferenceManifest(
                "video references require fixed displayCorners, output dimensions, and an exclusion mask"
            )
        }
        try alignment.validate()
        if !manifest.permitsRedistribution && !privateReference {
            throw FidelityError.privateReferenceAcknowledgementRequired
        }

        let actualHash: String
        if referenceURL.pathExtension.lowercased() == "m3u8" {
            let movie = try LocalHLS.materializeMovie(from: referenceURL)
            defer { try? FileManager.default.removeItem(at: movie) }
            actualHash = try ArtifactHash.sha256(url: movie)
        } else {
            actualHash = try ArtifactHash.sha256(url: referenceURL)
        }
        let expectedHash = manifest.analysisCopy.sha256.lowercased()
        guard actualHash == expectedHash else {
            throw FidelityError.referenceHashMismatch(expected: expectedHash, actual: actualHash)
        }

        let start = manifest.transition.anchors.foldStart.presentationTimeSeconds
        let end = manifest.transition.anchors.foldComplete.presentationTimeSeconds
        guard abs(startTime - start) < 1e-9 else {
            throw FidelityError.invalidReferenceManifest("--start-time does not match foldStart")
        }
        if let duration {
            guard abs(duration - (end - start)) < 1e-9 else {
                throw FidelityError.invalidReferenceManifest("--duration does not match foldStart/foldComplete")
            }
        }
        return manifest
    }
}
