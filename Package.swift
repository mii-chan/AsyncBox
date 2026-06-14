// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AsyncBox",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "AsyncBox",
            targets: ["AsyncBox"]
        ),
        .library(
            name: "AsyncBoxUI",
            targets: ["AsyncBoxUI"]
        ),
    ],
    targets: [
        .target(
            name: "AsyncBox"
        ),
        .target(
            name: "AsyncBoxUI",
            dependencies: ["AsyncBox"]
        ),
        .testTarget(
            name: "AsyncBoxTests",
            dependencies: ["AsyncBox"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
