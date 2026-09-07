// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StringMapCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "FingeringEngine", targets: ["FingeringEngine"]),
        .library(name: "ScorePipeline", targets: ["ScorePipeline"]),
        .executable(name: "stringmap-check", targets: ["StringMapCheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(name: "FingeringEngine"),
        .target(name: "ScorePipeline", dependencies: ["FingeringEngine", "ZIPFoundation"]),
        .executableTarget(name: "StringMapCheck", dependencies: ["ScorePipeline"]),
        .testTarget(name: "FingeringEngineTests", dependencies: ["FingeringEngine"]),
        .testTarget(name: "ScorePipelineTests", dependencies: ["ScorePipeline", "FingeringEngine", "ZIPFoundation"]),
    ]
)
