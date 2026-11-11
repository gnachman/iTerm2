#!/bin/bash
# Headless Foundation verification while the app-wide test host is unavailable.
set -euo pipefail
project_test_repo="$(cd "$(dirname "$0")/.." && pwd)"
project_test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/iterm-project-tests.XXXXXX")"
trap 'rm -rf "$project_test_tmp"' EXIT
project_test_developer="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"
sed '/@testable import iTerm2SharedARC/d' "$project_test_repo/ModernTests/ProjectSidebarTests.swift" > "$project_test_tmp/ProjectSidebarTests.swift"
sed '/@testable import iTerm2SharedARC/d' "$project_test_repo/ModernTests/ProjectWindowTests.swift" > "$project_test_tmp/ProjectWindowTests.swift"
cat > "$project_test_tmp/Stubs.swift" <<'SWIFT'
import Foundation
// The executable has no app host: only the app's defaults provider is replaced.
class iTermUserDefaults: NSObject {
    static func userDefaults() -> UserDefaults { UserDefaults(suiteName: "ProjectSidebarStandalone")! }
}
SWIFT
cat > "$project_test_tmp/main.swift" <<'SWIFT'
import XCTest
let suite = XCTestSuite(name: "Project Sidebars")
suite.addTest(ProjectSidebarTests.defaultTestSuite)
suite.addTest(ProjectWindowTests.defaultTestSuite)
suite.run()
exit(suite.testRun!.hasSucceeded ? 0 : 1)
SWIFT
xcrun swiftc -swift-version 5 -warnings-as-errors \
    -I "$project_test_developer/usr/lib" -L "$project_test_developer/usr/lib" \
    -F "$project_test_developer/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$project_test_developer/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$project_test_developer/usr/lib" \
    "$project_test_repo/sources/Toolbelt/iTermProjectDirectory.swift" \
    "$project_test_repo/sources/Toolbelt/iTermFileTreeDataSource.swift" \
    "$project_test_repo/sources/Toolbelt/iTermProjectWindowController.swift" \
    "$project_test_tmp/ProjectWindowTests.swift" \
    "$project_test_tmp/Stubs.swift" "$project_test_tmp/ProjectSidebarTests.swift" "$project_test_tmp/main.swift" \
    -o "$project_test_tmp/tests"
DYLD_FRAMEWORK_PATH="$project_test_developer/Library/PrivateFrameworks" "$project_test_tmp/tests"
