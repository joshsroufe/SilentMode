// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SilentMode",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "SilentMode", targets: ["SilentMode"])
    ],
    targets: [
        .executableTarget(
            name: "SilentMode",
            path: "Sources",
            exclude: ["SilentModeControl"],
            sources: ["SilentMode", "SilentModeShared"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AudioToolbox")
            ]
        )
    ]
)
