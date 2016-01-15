#!/usr/bin/env bash

set -euo pipefail

xcrun xcodebuild build test \
  NSUnbufferedIO=YES \
  -project iTerm2.xcodeproj \
  -scheme iTerm2 \
  -sdk macosx \
    | xcpretty -c -f `xcpretty-travis-formatter`
