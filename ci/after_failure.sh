#!/usr/bin/env bash

set -x

if ls /tmp/failed-* 1> /dev/null 2>&1; then
  cp tests/imgcat /tmp
  cp ci/accept.sh /tmp
  export PATH=$PATH:$PWD/tests
  cd /tmp
  source /tmp/diffs > diffs.txt
  tar cvfz - failed-*.png diffs.txt accept.sh | base64 -b 80
fi

