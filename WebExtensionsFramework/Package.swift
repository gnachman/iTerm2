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
            name: "BrowserExtensionShared",
            dependencies: [],
            path: "Shared",
            resources: [
                .copy("../Resources")
            ]
        ),
        .target(
            name: "WebExtensionsFramework",
            dependencies: ["BrowserExtensionShared"],
            path: "Sources",
            resources: [
                .copy("../Resources")
            ]
        ),
        .executableTarget(
            name: "APIGenerator",
            dependencies: ["BrowserExtensionShared"],
            path: "APIGenerator"
        ),
        .testTarget(
            name: "WebExtensionsFrameworkTests",
            dependencies: ["WebExtensionsFramework", "BrowserExtensionShared"],
            resources: [
                .copy("Resources")
            ]
        ),
    ]
)
