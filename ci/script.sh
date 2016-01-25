#!/usr/bin/env bash

set -euo pipefail

xcrun xcodebuild build test \
  NSUnbufferedIO=YES \
  -workspace iTerm2.xcworkspace \
  -scheme iTerm2 \
  -sdk macosx \
    | xcpretty -c -f `xcpretty-travis-formatter`
