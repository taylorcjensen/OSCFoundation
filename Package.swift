// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OSCFoundation",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "OSCFoundation",
            targets: ["OSCFoundation"]
        ),
    ],
    targets: [
        .target(
            name: "OSCFoundation"
        ),
        .testTarget(
            name: "OSCFoundationTests",
            dependencies: ["OSCFoundation"]
        ),
    ]
)
