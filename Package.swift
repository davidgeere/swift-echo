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
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        // Swift Testing framework
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
        // Type-erased Codable wrappers
        .package(url: "https://github.com/Flight-School/AnyCodable.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "Echo",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "AnyCodable", package: "AnyCodable"),
                "WebRTC"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        // Local WebRTC XCFramework with dSYM support
        .binaryTarget(
            name: "WebRTC",
            path: "Frameworks/WebRTC.xcframework"
        ),
        .testTarget(
            name: "EchoTests",
            dependencies: [
                "Echo",
                .product(name: "Testing", package: "swift-testing")
            ],
            resources: [
                .copy("Fixtures/Cassettes")
            ]
        )
    ]
)
