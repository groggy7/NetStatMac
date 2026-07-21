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
        .target(
            name: "NetStatCore",
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "NetStatBar",
            dependencies: ["NetStatCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "NetStatCoreTests",
            dependencies: ["NetStatCore"]
        )
    ]
)
