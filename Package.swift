// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pata",
    defaultLocalization: "zh-CN",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Pata", targets: ["PataApp"]),
        .library(name: "PataCore", targets: ["PataCore"]),
        .library(name: "PataKeychain", targets: ["PataKeychain"]),
        .library(name: "PataAudio", targets: ["PataAudio"]),
        .library(name: "PataMCP", targets: ["PataMCP"]),
        .library(name: "PataEditor", targets: ["PataEditor"]),
        .library(name: "PataUI", targets: ["PataUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.4.0"),
        .package(url: "https://github.com/nodes-app/swift-markdown-engine", from: "0.15.0")
    ],
    targets: [
        .target(
            name: "PataCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/PataCore"
        ),
        .target(
            name: "PataKeychain",
            path: "Sources/PataKeychain"
        ),
        .target(
            name: "PataAudio",
            dependencies: [
                "PataCore",
                "PataKeychain"
            ],
            path: "Sources/PataAudio"
        ),
        .target(
            name: "PataMCP",
            dependencies: [
                "PataCore"
            ],
            path: "Sources/PataMCP"
        ),
        .target(
            name: "PataEditor",
            dependencies: [
                "PataCore",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine")
            ],
            path: "Sources/PataEditor"
        ),
        .target(
            name: "PataUI",
            dependencies: [
                "PataCore",
                "PataKeychain",
                "PataAudio",
                "PataMCP",
                "PataEditor"
            ],
            path: "Sources/PataUI"
        ),
        .executableTarget(
            name: "PataApp",
            dependencies: [
                "PataUI"
            ],
            path: "Sources/PataApp"
        ),
        .testTarget(
            name: "PataTests",
            dependencies: [
                "PataCore",
                "PataKeychain",
                "PataAudio",
                "PataMCP"
            ],
            path: "Tests/PataTests"
        )
    ]
)
