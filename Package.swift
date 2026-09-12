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
        .target(name: "LidRippleOverlay", dependencies: ["LidRippleCore"]),
        .executableTarget(
            name: "LidRippleApp",
            dependencies: ["LidRippleCore", "LidRippleSensor", "LidRippleOverlay"]
        ),
        .testTarget(name: "LidRippleOverlayTests", dependencies: ["LidRippleOverlay"]),
        .target(name: "LidRippleCapture"),
        .testTarget(
            name: "LidRippleCaptureTests",
            dependencies: ["LidRippleCapture", "LidRippleOverlay"]
        ),
    ]
)
