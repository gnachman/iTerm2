#!/bin/sh
# Fast check of the Swift railroad port without building iTerm2.
set -e
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/railroad-check"
nice -n 19 swiftc -O tests/railroad/check/main.swift sources/RegexVisualization/Railroad/*.swift -o "$out"
"$out" tests/railroad "$@"
