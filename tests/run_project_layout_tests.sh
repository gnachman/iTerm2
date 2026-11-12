#!/bin/bash
# Exercise the real Objective-C layout calculator without launching the application.
set -euo pipefail
project_layout_repo="$(cd "$(dirname "$0")/.." && pwd)"
project_layout_tmp="$(mktemp -d "${TMPDIR:-/tmp}/iterm-project-layout.XXXXXX")"
trap 'rm -rf "$project_layout_tmp"' EXIT
mkdir -p "$project_layout_tmp/Sources/include" "$project_layout_tmp/Tests/LayoutTests"
cp "$project_layout_repo/sources/TerminalView/iTermLayoutCalculator.m" "$project_layout_tmp/Sources/"
cp "$project_layout_repo/sources/TerminalView/iTermLayoutCalculator.h" "$project_layout_tmp/Sources/include/"
sed 's/@testable import iTerm2SharedARC/import Layout/' "$project_layout_repo/ModernTests/iTermLayoutCalculatorTest.swift" > "$project_layout_tmp/Tests/LayoutTests/LayoutTests.swift"
cat > "$project_layout_tmp/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Layout", platforms: [.macOS(.v13)], targets: [
    .target(name: "Layout", path: "Sources", publicHeadersPath: "include", linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]),
    .testTarget(name: "LayoutTests", dependencies: ["Layout"])
])
SWIFT
swift test --package-path "$project_layout_tmp"
