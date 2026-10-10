// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MouseBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MouseCore", targets: ["MouseCore"]),
        .executable(name: "MouseBar", targets: ["MouseBar"]),
        .executable(name: "hidprobe", targets: ["hidprobe"]),
    ],
    targets: [
        // Pure logic. Swift 6 language mode, no IOKit.
        .target(name: "MouseCore"),
        // The only IOKit code. Swift 5 mode: C callbacks and CF types fight strict concurrency.
        .target(
            name: "MouseHID",
            dependencies: ["MouseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "hidprobe",
            dependencies: ["MouseCore", "MouseHID"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MouseBar",
            dependencies: ["MouseCore", "MouseHID"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MouseCoreTests",
            dependencies: ["MouseCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
