#!/bin/bash
# Compile the real watcher and its lifecycle tests without an app host or GUI.
set -euo pipefail
watch_test_repo="$(cd "$(dirname "$0")/.." && pwd)"
watch_test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/iterm-watch-tests.XXXXXX")"
trap 'rm -rf "$watch_test_tmp"' EXIT
watch_test_developer="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"
if [[ "${1:-}" == "--native" ]]; then
    xcrun swiftc -swift-version 5 -warnings-as-errors \
        "$watch_test_repo/sources/Toolbelt/iTermFileTreeWatcher.swift" \
        "$watch_test_repo/tests/file_tree_watcher_native_test.swift" -o "$watch_test_tmp/native"
    "$watch_test_tmp/native" "$watch_test_repo/tmp"
    exit
fi
sed '/@testable import iTerm2SharedARC/d' "$watch_test_repo/ModernTests/FileTreeWatcherTests.swift" > "$watch_test_tmp/Tests.swift"
cat > "$watch_test_tmp/main.swift" <<'SWIFT'
import XCTest
let suite = FileTreeWatcherTests.defaultTestSuite
suite.run()
exit(suite.testRun!.hasSucceeded ? 0 : 1)
SWIFT
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -I "$watch_test_developer/usr/lib" -L "$watch_test_developer/usr/lib" \
    -F "$watch_test_developer/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$watch_test_developer/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$watch_test_developer/usr/lib" \
    "$watch_test_repo/sources/Toolbelt/iTermFileTreeWatcher.swift" \
    "$watch_test_tmp/Tests.swift" "$watch_test_tmp/main.swift" -o "$watch_test_tmp/tests"
DYLD_FRAMEWORK_PATH="$watch_test_developer/Library/PrivateFrameworks" "$watch_test_tmp/tests"
