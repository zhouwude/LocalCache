// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LocalCache",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "LocalCache",
            targets: ["LocalCache"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LocalCache",
            dependencies: [],
            path: ".",
            exclude: [
                "LocalCacheTests",
                "README.md",
                "Package.swift",
                "IMPLEMENTATION_SUMMARY.md",
                "TEST_IMPROVEMENTS_SUMMARY.md"
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LocalCacheTests",
            dependencies: ["LocalCache"],
            path: "LocalCacheTests",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
