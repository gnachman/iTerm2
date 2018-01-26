#!/usr/bin/env bash

set -euo pipefail

xcrun xcodebuild build test \
  NSUnbufferedIO=YES \
  -scheme iTerm2 \
  -sdk macosx \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=  | sed -e 's,usr/bin/clang .* -c,usr/bin/clang [redacted] -c,'
