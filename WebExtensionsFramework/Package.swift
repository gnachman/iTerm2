// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WebExtensionsFramework",
    platforms: [
        .macOS(.v12) // Required for proxy support
    ],
    products: [
        .library(
            name: "WebExtensionsFramework",
            targets: ["WebExtensionsFramework"]
        ),
    ],
    dependencies: [
        // No external dependencies for MVP
    ],
    targets: [
        .target(
            name: "WebExtensionsFramework",
            dependencies: []
        ),
        .testTarget(
            name: "WebExtensionsFrameworkTests",
            dependencies: ["WebExtensionsFramework"],
            resources: [
                .copy("Resources")
            ]
        ),
    ]
)
