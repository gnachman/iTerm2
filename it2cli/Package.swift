// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "it2cli",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "it2", targets: ["it2"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "ProtobufRuntime",
            path: "Sources/ProtobufRuntime",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .unsafeFlags(["-fno-objc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "it2",
            dependencies: [
                "ProtobufRuntime",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/it2"
        )
    ]
)
