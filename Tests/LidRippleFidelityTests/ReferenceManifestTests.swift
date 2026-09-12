import Foundation
import Testing
@testable import lidripple_fidelity

@Test func videoReferenceRequiresManifestAndExplicitPrivateAcknowledgement() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidripple-manifest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let video = temporary.appendingPathComponent("reference.mp4")
    try Data("synthetic reference".utf8).write(to: video)

    #expect(throws: FidelityError.referenceManifestRequired) {
        try ReferenceValidation.validate(
            referenceURL: video,
            manifestURL: nil,
            startTime: 1,
            duration: 1,
            privateReference: false
        )
    }

    let manifest = temporary.appendingPathComponent("reference.json")
    try manifestJSON(hash: try ArtifactHash.sha256(url: video)).write(
        to: manifest,
        atomically: true,
        encoding: .utf8
    )
    #expect(throws: FidelityError.privateReferenceAcknowledgementRequired) {
        try ReferenceValidation.validate(
            referenceURL: video,
            manifestURL: manifest,
            startTime: 1,
            duration: 1,
            privateReference: false
        )
    }
    let accepted = try ReferenceValidation.validate(
        referenceURL: video,
        manifestURL: manifest,
        startTime: 1,
        duration: 1,
        privateReference: true
    )
    #expect(accepted?.permitsRedistribution == false)
}

@Test func referenceValidationRejectsHashAndAnchorMismatch() throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("lidripple-manifest-mismatch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let video = temporary.appendingPathComponent("reference.mov")
    try Data("actual".utf8).write(to: video)
    let manifest = temporary.appendingPathComponent("reference.json")
    try manifestJSON(hash: String(repeating: "0", count: 64)).write(
        to: manifest,
        atomically: true,
        encoding: .utf8
    )

    #expect(throws: FidelityError.referenceHashMismatch(
        expected: String(repeating: "0", count: 64),
        actual: try ArtifactHash.sha256(url: video)
    )) {
        try ReferenceValidation.validate(
            referenceURL: video,
            manifestURL: manifest,
            startTime: 1,
            duration: 1,
            privateReference: true
        )
    }
}

private func manifestJSON(hash: String) -> String {
    """
    {
      "schemaVersion": 1,
      "source": {
        "title": "Synthetic",
        "publisher": "Tests",
        "analyzedVariantURL": "https://example.invalid/reference.mp4",
        "rights": {
          "copyrightHolder": "Tests",
          "licenseIdentifier": null,
          "redistributionAndDerivativePermission": "not-established"
        }
      },
      "analysisCopy": { "sha256": "\(hash)" },
      "technical": { "presentationTimeScale": 1000 },
      "transition": {
        "anchors": {
          "foldStart": { "presentationTimeTicks": 1000, "presentationTimeSeconds": 1.0 },
          "foldComplete": { "presentationTimeTicks": 2000, "presentationTimeSeconds": 2.0 }
        }
      },
      "alignment": {
        "outputWidth": 2,
        "outputHeight": 2,
        "displayCorners": {
          "topLeft": {"x": 0, "y": 0},
          "topRight": {"x": 1, "y": 0},
          "bottomRight": {"x": 1, "y": 1},
          "bottomLeft": {"x": 0, "y": 1}
        },
        "exclusionPolygons": []
      }
    }
    """
}
