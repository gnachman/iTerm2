// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "cc-status",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "cc-status", targets: ["cc-status"])
    ],
    targets: [
        .executableTarget(
            name: "cc-status",
            path: "Sources/cc-status"
        )
    ]
)
