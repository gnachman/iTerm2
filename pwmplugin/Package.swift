// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iterm2-keepassxc-adapter",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "iterm2-keepassxc-adapter",
            targets: ["iterm2-keepassxc-adapter"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "iterm2-keepassxc-adapter",
            path: "Sources",
            sources: [
                "iterm2-keepassxc-adapter/main.swift",
                "PasswordManagerProtocol/PasswordManagerProtocol.swift"
            ]
        ),
        .testTarget(
            name: "iterm2-keepassxc-adapterTests",
            dependencies: []
        )
    ]
)
