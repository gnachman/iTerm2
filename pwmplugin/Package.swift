// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iterm2-password-manager-adapters",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "iterm2-keepassxc-adapter",
            targets: ["iterm2-keepassxc-adapter"]
        ),
        .executable(
            name: "iterm2-bitwarden-adapter",
            targets: ["iterm2-bitwarden-adapter"]
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
        .executableTarget(
            name: "iterm2-bitwarden-adapter",
            path: "Sources/iterm2-bitwarden-adapter"
        ),
        .testTarget(
            name: "iterm2-keepassxc-adapterTests",
            dependencies: []
        ),
        .testTarget(
            name: "iterm2-bitwarden-adapterTests",
            dependencies: []
        )
    ]
)
