#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/iterm-git-scanner-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
frameworks="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
test_lib="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib"
swiftc -swift-version 5 -D GIT_WORKTREE_SCANNER_STANDALONE -I "$test_lib" -L "$test_lib" -Xlinker -rpath -Xlinker "$test_lib" -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks" -warnings-as-errors sources/Toolbelt/iTermGitWorktreeScanner.swift ModernTests/GitWorktreeScannerTests.swift -o "$build_dir/tests"
"$build_dir/tests"
