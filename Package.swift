// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetStatBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NetStatBar", targets: ["NetStatBar"])
    ],
    targets: [
        .executableTarget(
            name: "NetStatBar",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
