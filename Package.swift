// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "OpenBar",
            targets: ["OpenBar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "OpenBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/OpenBar",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
