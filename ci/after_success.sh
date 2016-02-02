#!/usr/bin/env bash

set -euo pipefail

bundle exec slather coverage \
    --input-format profdata \
    --scheme iTerm2 \
    iTerm2.xcodeproj
