#!/usr/bin/env bash

set -euo pipefail

xcrun xcodebuild build test \
  NSUnbufferedIO=YES \
  -workspace iTerm2.xcworkspace \
  -scheme iTerm2 \
  -sdk macosx \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    | xcpretty -c -f `xcpretty-travis-formatter`
