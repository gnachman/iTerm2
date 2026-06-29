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
        .executable(
            name: "iterm2-keeper-adapter",
            targets: ["iterm2-keeper-adapter"]
        ),
        .executable(
            name: "iterm2-test-adapter",
            targets: ["iterm2-test-adapter"]
        ),
    ],
    targets: [
        .target(
            name: "PasswordManagerProtocol",
            path: "Sources/PasswordManagerProtocol"
        ),
        .executableTarget(
            name: "iterm2-keepassxc-adapter",
            dependencies: ["PasswordManagerProtocol"],
            path: "Sources/iterm2-keepassxc-adapter"
        ),
        .executableTarget(
            name: "iterm2-bitwarden-adapter",
            dependencies: ["PasswordManagerProtocol"],
            path: "Sources/iterm2-bitwarden-adapter"
        ),
        .executableTarget(
            name: "iterm2-keeper-adapter",
            dependencies: ["PasswordManagerProtocol"],
            path: "Sources/iterm2-keeper-adapter"
        ),
        .executableTarget(
            name: "iterm2-test-adapter",
            dependencies: ["PasswordManagerProtocol"],
            path: "Sources/iterm2-test-adapter"
        ),
        .testTarget(
            name: "iterm2-keepassxc-adapterTests",
            dependencies: []
        ),
        .testTarget(
            name: "iterm2-bitwarden-adapterTests",
            dependencies: []
        ),
        .testTarget(
            name: "iterm2-keeper-adapterTests",
            dependencies: ["iterm2-keeper-adapter"]
        )
    ]
)
