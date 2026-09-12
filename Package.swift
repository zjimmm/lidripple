// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "lidripple",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LidRippleCore", targets: ["LidRippleCore"]),
        .library(name: "LidRippleSensor", targets: ["LidRippleSensor"]),
        .library(name: "LidRippleTrace", targets: ["LidRippleTrace"]),
        .executable(name: "lidripple-trace", targets: ["lidripple-trace"]),
        .library(name: "LidRippleOverlay", targets: ["LidRippleOverlay"]),
        .library(name: "LidRippleCapture", targets: ["LidRippleCapture"]),
        .library(name: "LidRippleRenderer", targets: ["LidRippleRenderer"]),
        .library(name: "LidRippleIntegration", targets: ["LidRippleIntegration"]),
        .executable(name: "lidripple-preview", targets: ["lidripple-preview"]),
    ],
    targets: [
        .target(name: "LidRippleCore"),
        .target(name: "LidRippleSensor", dependencies: ["LidRippleCore"]),
        .target(name: "LidRippleTrace", dependencies: ["LidRippleCore"]),
        .executableTarget(
            name: "lidripple-trace",
            dependencies: ["LidRippleCore", "LidRippleSensor", "LidRippleTrace"]
        ),
        .testTarget(
            name: "LidRippleCoreTests",
            dependencies: ["LidRippleCore", "LidRippleSensor", "LidRippleTrace"]
        ),
        .testTarget(name: "LidRippleTraceTests", dependencies: ["LidRippleTrace", "LidRippleCore"]),
        .target(
            name: "LidRippleOverlay",
            dependencies: ["LidRippleCore", "LidRippleCapture", "LidRippleRenderer"]
        ),
        .executableTarget(
            name: "LidRippleApp",
            dependencies: [
                "LidRippleCore",
                "LidRippleSensor",
                "LidRippleOverlay",
                "LidRippleCapture",
                "LidRippleIntegration",
            ]
        ),
        .testTarget(name: "LidRippleOverlayTests", dependencies: ["LidRippleOverlay"]),
        .target(name: "LidRippleCapture"),
        .testTarget(
            name: "LidRippleCaptureTests",
            dependencies: ["LidRippleCapture", "LidRippleOverlay"]
        ),
        .target(
            name: "LidRippleRenderer",
            dependencies: ["LidRippleCore", "LidRippleCapture"]
        ),
        .target(
            name: "LidRippleIntegration",
            dependencies: ["LidRippleCore", "LidRippleCapture"]
        ),
        .testTarget(
            name: "LidRippleIntegrationTests",
            dependencies: ["LidRippleIntegration", "LidRippleCapture", "LidRippleTrace"]
        ),
        .testTarget(
            name: "LidRippleRendererTests",
            dependencies: ["LidRippleRenderer"],
            resources: [.process("Goldens")]
        ),
        .executableTarget(
            name: "lidripple-preview",
            dependencies: ["LidRippleCore", "LidRippleOverlay", "LidRippleRenderer"]
        ),
    ]
)
