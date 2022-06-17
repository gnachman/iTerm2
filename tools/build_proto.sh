#!/bin/bash
# Note: you must have mypy-protobuf installed.
# pip3 install mypy-protobuf
# pip3 install protobuf
SOURCE=proto
GENFILES=sources/proto
die() {
  echo "error: protoc 3.19 required"
  echo "You have $(which protoc) with version $(protoc --version)"
  exit 1
}
(protoc --version | grep "libprotoc 3.19" > /dev/null) || die
protoc --proto_path="$SOURCE" --objc_out="$GENFILES" --python_out=api/library/python/iterm2/iterm2 "$SOURCE"/api.proto --mypy_out=api/library/python/iterm2/iterm2
