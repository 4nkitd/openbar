// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexBarLite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CodexBarLite",
            targets: ["CodexBarLite"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "CodexBarLite",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/OpenBar"
        )
    ]
)
