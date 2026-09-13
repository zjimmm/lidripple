import Foundation
import Testing
@testable import lidripple_fidelity

@Test func optionsResolveRelativePathsAndOptionalControls() throws {
    let root = URL(fileURLWithPath: "/tmp/lidripple-fidelity-options", isDirectory: true)
    let options = try FidelityOptions.parse(
        [
            "--reference", "duo.mov",
            "--output-dir", "result",
            "--frames", "61",
            "--start-time", "12.5",
            "--duration", "0.62",
            "--direction", "opening",
            "--curve", "smoothstep",
            "--tuning", "tuning.json",
            "--reference-manifest", "reference.json",
            "--private-reference",
        ],
        currentDirectory: root
    )

    #expect(options.referenceURL.path == "/tmp/lidripple-fidelity-options/duo.mov")
    #expect(options.outputDirectory.path == "/tmp/lidripple-fidelity-options/result")
    #expect(options.frameCount == 61)
    #expect(options.duration == 0.62)
    #expect(options.startTime == 12.5)
    #expect(options.direction == .opening)
    #expect(options.curve == .smoothstep)
    #expect(options.tuningURL?.path == "/tmp/lidripple-fidelity-options/tuning.json")
    #expect(options.referenceManifestURL?.path == "/tmp/lidripple-fidelity-options/reference.json")
    #expect(options.privateReference)
}

@Test func optionsRejectMissingAndInvalidValues() {
    let root = URL(fileURLWithPath: "/tmp")
    #expect(throws: FidelityError.missingOption("--reference")) {
        try FidelityOptions.parse(
            ["--output-dir", "out"],
            currentDirectory: root
        )
    }
    #expect(throws: FidelityError.invalidFrameCount(1)) {
        try FidelityOptions.parse(
            [
                "--reference", "reference",
                "--output-dir", "out",
                "--frames", "1",
            ],
            currentDirectory: root
        )
    }
    #expect(throws: FidelityError.invalidDirection("sideways")) {
        try FidelityOptions.parse(
            [
                "--reference", "reference",
                "--output-dir", "out",
                "--direction", "sideways",
            ],
            currentDirectory: root
        )
    }
    #expect(throws: FidelityError.invalidStartTime(-1)) {
        try FidelityOptions.parse(
            [
                "--reference", "reference",
                "--output-dir", "out",
                "--start-time", "-1",
            ],
            currentDirectory: root
        )
    }
    #expect(throws: FidelityError.invalidCurve("springy")) {
        try FidelityOptions.parse(
            [
                "--reference", "reference",
                "--output-dir", "out",
                "--curve", "springy",
            ],
            currentDirectory: root
        )
    }
}
