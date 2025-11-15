// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Echo",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Echo",
            targets: ["Echo"]
        )
    ],
    dependencies: [
        // HTTP client for Responses API
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
        // Advanced stream operations for async sequences
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0")
        // Swift Testing is now built into Swift 6 - no package needed!
    ],
    targets: [
        .target(
            name: "Echo",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EchoTests",
            dependencies: [
                "Echo"
                // Swift Testing is now built-in with Swift 6
            ],
            resources: [
                .copy("Fixtures/Cassettes")
            ]
        )
    ]
)
