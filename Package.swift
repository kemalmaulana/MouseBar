// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MouseBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MouseCore", targets: ["MouseCore"]),
        .library(name: "MouseLogi", targets: ["MouseLogi"]),
        .executable(name: "MouseBar", targets: ["MouseBar"]),
        .executable(name: "hidprobe", targets: ["hidprobe"]),
        .executable(name: "logiprobe", targets: ["logiprobe"]),
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
        // Rust static library (OpenLogi HID++ over a C ABI), built by Scripts/build-logi.sh. Git-ignored.
        .binaryTarget(name: "MouseBarLogiFFI", path: "Vendor/MouseBarLogi.xcframework"),
        // Swift bridge to the Logitech FFI. Swift 6 mode; every C call runs on one private serial queue.
        .target(
            name: "MouseLogi",
            dependencies: ["MouseCore", "MouseBarLogiFFI"],
            linkerSettings: [
                // The static library's native-static-libs, minus -lSystem/-lc/-lm that Swift links anyway.
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Foundation"),
                .linkedLibrary("iconv"),
                .linkedLibrary("objc"),
            ]
        ),
        .executableTarget(
            name: "logiprobe",
            dependencies: ["MouseLogi"]
        ),
        .executableTarget(
            name: "hidprobe",
            dependencies: ["MouseCore", "MouseHID"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MouseBar",
            dependencies: ["MouseCore", "MouseHID", "MouseLogi"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MouseCoreTests",
            dependencies: ["MouseCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
