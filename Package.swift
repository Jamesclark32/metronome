// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Metronome",
    platforms: [.macOS(.v13)],
    products: [
        // The app executable is renamed to Metronome inside the bundle; SwiftPM
        // cannot build both "Metronome" and "metronome" into one directory on a
        // case-insensitive file system.
        .executable(name: "MetronomeApp", targets: ["MetronomeApp"]),
        .executable(name: "metronome", targets: ["MetronomeCLI"]),
        .library(name: "MetronomeCore", targets: ["MetronomeCore"]),
    ],
    targets: [
        .target(name: "MetronomeCore"),
        .executableTarget(name: "MetronomeApp", dependencies: ["MetronomeCore"]),
        .executableTarget(name: "MetronomeCLI", dependencies: ["MetronomeCore"]),
        .testTarget(name: "MetronomeCoreTests", dependencies: ["MetronomeCore"]),
    ]
)
