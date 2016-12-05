#!/usr/bin/env bash

set -euo pipefail
set -x

if ls /tmp/failed-* 1> /dev/null 2>&1; then
  cp tests/imgcat /tmp
  export path=($path $PWD/tests)
  cd /tmp
  source /tmp/diffs > diffs.txt
  tar cvfz failed-images.tgz failed-*.png diffs.txt
  curl -F "file=@failed-images.tgz" https://file.io
fi

