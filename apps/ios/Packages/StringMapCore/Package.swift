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
    ],
    targets: [
        .target(name: "FingeringEngine"),
        .target(name: "ScorePipeline", dependencies: ["FingeringEngine"]),
        .testTarget(name: "FingeringEngineTests", dependencies: ["FingeringEngine"]),
        .testTarget(name: "ScorePipelineTests", dependencies: ["ScorePipeline", "FingeringEngine"]),
    ]
)
