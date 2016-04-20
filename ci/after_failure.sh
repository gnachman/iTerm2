#!/usr/bin/env bash

set -euo pipefail
set -x

if ls /tmp/failed-* 1> /dev/null 2>&1; then
  cd /tmp
  tar cvfz failed-images.tgz failed-*.png
  curl -F "file=@failed-images.tgz" https://file.io
fi

